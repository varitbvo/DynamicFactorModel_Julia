
### Functions that transform each series to be stationary.

function stationarizeData(tcode::Integer, tseries::DataFrame)

datevec = tseries[:,1]
    if tcode == 1
        sout = tseries
    elseif tcode == 2
        sout = [missing; diff.(tseries[:,2])]
    elseif tcode == 3
        sout = [missing; missing; diff(diff.(tseries[:,2]))]
    elseif tcode == 4
        sout = log(tseries)
    elseif tcode == 5
        sout = [missing; diff(log.(tseries[:,2]))]
    elseif tcode == 6
        sout = [missing; missing; diff(diff(log.(tseries[:,2])))]
    elseif tcode == 7
        sout = [missing; missing; diff.(tseries[2:end,2]./tseries[1:end-1,2] .- 1.0)]
    else
        throw(ArgumentError(tcode, "Invalid transformation code"))
    end
    return DataFrame(date = datevec, value = sout)

end
function transform_data(x::String, y::Integer)
    Tcode = y

    fred = get_data(Fred("266c597cbf3d25f366b082b4bf5161fe"), x)
    df = fred.data[:, [3,4]]
    title = fred.title

    if Tcode == 2
        df = diff_ts(df)
    elseif Tcode == 4
        df = log_ts(df)
    elseif Tcode == 5
        df = log_diff(df)
    elseif Tcode == 6
        df = log_diff_diff(df)
    end

    symbol = Symbol(x)
    rename!(df, :value => symbol)

    return df, title
end
# TODO: declare type of seriescodes for speeed


function download_and_transform_DFM(seriescodes, startdate, enddate)
    daterange = [Date(startdate):Dates.Month(1):Date(enddate)...]

global dataout = DataFrame(date = daterange::Array{Date,1})
    for jj = 1: size(seriescodes,1)
    #print(jj)
        #global dataout
        ser = seriescodes[jj,1]
        tcode = seriescodes[jj,2]
        try
            #tmpFrame = DataFrame([date = Array{Date,1}, value = Array{Float64,1}])
            tmpData = get_data(f,ser, observation_start = startdate, observation_end = enddate, frequency = "m", aggregation_method = "avg")
            tmpFrame = tmpData.data[:,3:4]

            tmpFrame= stationarizeData(tcode, tmpFrame) # stationary transform
    #    show(tmpFrame)
            rename!(tmpFrame, "value" => tmpData.id)

            dataout = outerjoin(dataout, tmpFrame, on = "date")
        #push!(pseries, tmpData)
        catch
            #this prints series names that don't exist in FRED, which we may have to update
            println(ser )
        end
    end
return dataout
end
