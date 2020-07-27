# generally: QuantEcon Kalman filter code but with adds external variable to Kalman filter and an error checking function

mutable struct Kalman
    A
    G
    Q
    R
    E # New matrix for external variable
    k
    n
    cur_x_hat
    cur_sigma
end


# Initializes current mean and cov to zeros
function Kalman(A, G, Q, R, E )
    k = size(G, 1)
    n = size(G, 2)
    xhat = n == 1 ? zero(eltype(A)) : zeros(n)
    Sigma = n == 1 ? zero(eltype(A)) : zeros(n, n)
    return Kalman(A, G, Q, R, E, k, n, xhat, Sigma)
end

function set_state!(k::Kalman, x_hat, Sigma)
    k.cur_x_hat = x_hat
    k.cur_sigma = Sigma
    Nothing
end

### Our function doesn't work when we have some missing external regressors.
function prior_to_filtered!(k::Kalman, y::AbstractVector, external = 1)
    # simplify notation
    G, R, E = k.G, k.R, k.E
    x_hat, Sigma = k.cur_x_hat, k.cur_sigma

    ### Change NaN into missing
    y = replace(y, NaN => missing)

    ### Deal with missing observation (missing)
    if size(y) != size(collect(skipmissing(y)))
        j = Array{Bool}(undef,length(y))
        l = ismissing.(y)
        for i in 1:length(y)
            j[i] = !l[i]
        end

        ## Change dimension of valid input, and matrices
        y = y[j]
        G = G[j,:]
        R = R[j,j]
        E = E[j,:]
    end

    # and then update
    A = Sigma*G'
    B = G*Sigma*G' + R
    M = A / B

    k.cur_x_hat = x_hat + M * (y - (G * x_hat) - (E * (external))) ### Add external variables
    k.cur_sigma = Sigma - M * G * Sigma
    Nothing
end

function filtered_to_forecast!(k::Kalman)
    # simplify notation
    A, Q = k.A, k.Q
    x_hat, Sigma = k.cur_x_hat, k.cur_sigma

    # and then update
    k.cur_x_hat = A * x_hat
    k.cur_sigma = A * Sigma * A' + Q
    Nothing
end

function log_likelihood(k::Kalman, y::AbstractVector, external = 1)
    # Simplify notation
    G, R, E = k.G, k.R, k.E
    x_hat, Sigma = k.cur_x_hat, k.cur_sigma

    ### Change NaN into missing
    y = replace(y, NaN => missing)

    ### Deal with missing observation (missing)
    if size(y) != size(collect(skipmissing(y)))
        j = Array{Bool}(undef,length(y))
        k = ismissing.(y)
        for i in 1:length(y)
            j[i] = !k[i]
        end
        ## Change dimension of valid input, and matrices
        y = y[j]
        G = G[j,:]
        R = R[j,j]
        E = E[j,:]
        println(y)
        println(G)
        println(R)
        println(E)
    end

    eta = y - G*x_hat - E*external # forecast error
    P = G*Sigma*G' + R # covariance matrix of forecast error
    logL = - (length(y)*log(2pi) + logdet(P) .+ eta'/P*eta)[1]/2
    return logL
end

function compute_loglikelihood(kn::Kalman, y::AbstractMatrix, external = 1)
    T = size(y, 2)
    logL = 0


    # forecast and update
    if external == 1
        for t in 1:T
            logL = logL + log_likelihood(kn, y[:,t])
            update!(kn, y[:, t])
        end
    else
        for t in 1:T
            logL = logL + log_likelihood(kn, y[:,t], external[:,t])
            update!(kn, y[:, t], external[:,t])
        end
    end

    return logL
end

function update!(k::Kalman, y, external = 1)
    prior_to_filtered!(k, y, external)
    filtered_to_forecast!(k)
    Nothing
end

function smooth(kn::Kalman, y::DataFrame, external::DataFrame)
    G, R = kn.G, kn.R

    T = size(y, 2)
    n = kn.n
    x_filtered = Matrix{Float64}(undef, n, T)
    sigma_filtered = Array{Float64}(undef, n, n, T)
    sigma_forecast = Array{Float64}(undef, n, n, T)
    logL = 0
    # forecast and update
    for t in 1:T
        logL = logL + log_likelihood(kn, y[:, t], external[:,t])
        prior_to_filtered!(kn, y[:, t], external[:,t])
        x_filtered[:, t], sigma_filtered[:, :, t] = kn.cur_x_hat, kn.cur_sigma
        filtered_to_forecast!(kn)
        sigma_forecast[:, :, t] = kn.cur_sigma
    end
    # smoothing
    x_smoothed = copy(x_filtered)
    sigma_smoothed = copy(sigma_filtered)
    for t in (T-1):-1:1
        x_smoothed[:, t], sigma_smoothed[:, :, t] =
            go_backward(kn, x_filtered[:, t], sigma_filtered[:, :, t],
                        sigma_forecast[:, :, t], x_smoothed[:, t+1],
                        sigma_smoothed[:, :, t+1])
    end

    return x_smoothed, logL, sigma_smoothed
end

function go_backward(k::Kalman, x_fi::Vector,
                     sigma_fi::Matrix, sigma_fo::Matrix,
                     x_s1::Vector, sigma_s1::Matrix)
    A = k.A
    temp = sigma_fi*A'/sigma_fo
    x_s = x_fi + temp*(x_s1-A*x_fi)
    sigma_s = sigma_fi + temp*(sigma_s1-sigma_fo)*temp'
    return x_s, sigma_s
end

function check_kalman(k::Kalman, y::DataFrame)
    ### Initiate error counter
    counter = 0

    ### Checking type of input
    if typeof(G) != Array{Float64,1} && typeof(G) != Array{Float64,2} &&
        typeof(G) != Array{Int64,1} && typeof(G) != Array{Int64,2}
        return "G should be a matrix."
    end
    n = size(G,1)
    r = size(G,2)

    if r == 1
        if typeof(A) != Array{Float64,1} && typeof(A) != Array{Int64,1}
            println("A has to be 1x1 matrix.")
            counter = counter + 1
        end
        if typeof(Q) != Array{Float64,1} && typeof(Q) != Array{Int64,1}
            println("Q has to be 1x1 matrix.")
            counter = counter + 1
        end
    else
        if typeof(A) != Array{Float64,2} && typeof(A) != Array{Int64, 2}
            println("A has to be a matrix.")
            counter = counter + 1
        end
        if typeof(Q) != Array{Float64,2} && typeof(Q) != Array{Int64, 2}
            println("Q has to be a matrix.")
            counter = counter + 1
        end
        if size(A) != (r,r)
            println("A should be $r x $r square matrix.")
            counter = counter + 1
        end
        if size(Q) != (r,r)
            println("Q should be $r x $r square matrix.")
            counter = counter + 1
        end
    end

    if n == 1
        if typeof(R) != Array{Float64,1} && typeof(R) != Array{Int64,1}
            println("R has to be 1x1 matrix.")
            counter = counter + 1
        end
    else
        if typeof(R) != Array{Float64,2} && typeof(R) != Array{Int64,2}
            println("R has to be a matrix.")
            counter = counter + 1
        end
        if size(R) != (n,n)
            println("R should be $n x $n square matrix.")
            counter = counter + 1
        end
    end

    if size(E,1) != n
        println("E should have $r rows.")
        counter = counter + 1
    end

    ### Checking the dimension of dataset
    if (size(y,1) != n)
        println("observation should be $r x 1 matrix.")
        counter = counter + 1
    end


    ### Result of dianostic
    if counter == 0
        return "We set up correctly!"
    end
    return "the setup should be as specified above."
end
