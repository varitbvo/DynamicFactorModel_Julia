using LinearAlgebra
using Plots
using DataFrames, CSV, HypothesisTests
using Dates
using FredData
# git for Fred Data: https://github.com/micahjsmith/FredData.jl
# i modified my local version to suppress some annoying warnings when metadata was missing

include("kalman_vbes.jl")
include("DFMDataFunctions.jl")

f = Fred("266c597cbf3d25f366b082b4bf5161fe")
seriescodes = DataFrame!(CSV.File("fred_mnemonics_tcodes_and_blocks.csv"; normalizenames=true, types = [String, Int, String]))


startdate = "1959-01-01"
enddate = "2019-09-01"
# the ellipses at the end of
#=
daterange = [Date(startdate):Dates.Month(1):Date(enddate)...]

# global pseries = []

dataout = DataFrame(date = daterange)

nsers = size(m_seriescodes,1)
#dataout = DataFrame(date = Date[], val = Any[])
# grab the first series



for jj = 1:nsers
#print(jj)
global dataout
ser = m_seriescodes[jj,1]
tcode = m_seriescodes[jj,2]
try
    tmpData = get_data(f,ser, observation_start = startdate, observation_end = enddate, frequency = "m", aggregation_method = "avg")
    tmpFrame = tmpData.data[:,3:4]
#    show(tmpFrame)
    rename!(tmpFrame, "value" => tmpData.id)
    dataout = outerjoin(dataout, tmpFrame, on = "date")
    #push!(pseries, tmpData)
catch
    #this prints series names that don't exist in FRED, which we may have to update
    println(ser )
end
end
=#
# TODO: find a better way of downloading the data -- maybe in R, or updating the Fred pull tool, because it's very inconsistent about what it's able to pull and the CSV writing is far slower than you'd expect
dataout = download_and_transform_DFM(seriescodes, startdate, enddate)
datestr = Dates.format(today(), "yyyy_mm_dd")
datavintage = "dfm_data_$datestr.csv"
CSV.write(datavintage, dataout)
