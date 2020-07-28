# helper functions for setting up and running the Kalman filter model
# adapted from Matlab code from NY Fed's DFM

function blkdig(vararg)
    stop_row = 0
    stop_col = 0
    column = 0
    row = 0
    for i in 1:length(vararg)
        column = column + size(vararg[i],2)
        row = row + size(vararg[i],1)
    end

    blk = zeros(row, column)

    for i in 1:length(vararg)
        mat_comp = vararg[i]
        for j in 1:size(mat_comp, 2)
            for k in 1:size(mat_comp, 1)
                blk[stop_row + k, stop_col + j] = mat_comp[k,j]
            end
        end
        stop_row = stop_row + size(mat_comp,1)
        stop_col = stop_col + size(mat_comp,2)
    end

    return blk
end



function sort_vec(blocks)
    uniq = [ blocks[1,:]]

    for i in 2:size(blocks,1)
        sum = 0
        for j in 1:size(uniq,1)
            sum = sum + (blocks[i,:] == uniq[j])
        end
        if sum == 0
            push!(uniq, blocks[i,:])
        end
    end
    return uniq
end

function ismember(blocks, str)
    idx = []
    for i in 1:size(blocks,1)
        if blocks[i,:] == str
            push!(idx, i)
        end
    end
    return idx
end
#=
function demean_series(series::Array{Float64,1})
    series = replace(series, NaN => missing) # handle NaN and missing
    temp_mean = mean(skipmissing(series))
    #println(temp_mean)
    for j in 1:size(series,1)
        temp = series[j] - temp_mean
        seriesout = replace(series, series[j] => temp)
    end
    return seriesout
end

function demeaned_dataset(df::DataFrame)
    global df_demean = DataFrame(date = df[:,1])
    for j in 2:size(df,2)
        tmp_series = demean_series(df[:,j])
    series = replace(series, NaN => missing) # handle NaN and missing
    temp_mean = mean(skipmissing(series))
    #println(temp_mean)
    for j in 1:size(series,1)
        temp = series[j] - temp_mean
        seriesout = replace(series, series[j] => temp)
    end
    return seriesout
end
=#
