using LinearAlgebra
using Plots
using DataFrames, CSV, HypothesisTests
using Dates

########################################

using Printf
import HTTP
import JSON

export
       # Fred object
       Fred, get_api_url, set_api_url!, get_api_key,

       # FredSeries object
       FredSeries,

       # Download data
       get_data

const MAX_ATTEMPTS       = 3
const FIRST_REALTIME     = Date(1776,07,04)
const LAST_REALTIME      = Date(9999,12,31)
const EARLY_VINTAGE_DATE = "1991-01-01"
const DEFAULT_API_URL    = "https://api.stlouisfed.org/fred/"
const API_KEY_LENGTH     = 32
const KEY_ENV_NAME       = "FRED_API_KEY"
const KEY_FILE_NAME      = ".freddatarc"

# Fred connection type
"""
A connection to the Fred API.
Constructors
------------
- `Fred()`: Key detected automatically. First, looks for the environment variable
    FRED_API_KEY, then looks for the file ~/.freddatarc.
- `Fred(key::AbstractString)`: User specifies key directly
Arguments
---------
- `key`: Registration key provided by the Fred.
Notes
-----
- Set the API url with `set_api_url!(f::Fred, url::AbstractString)`
"""
mutable struct Fred
    key::AbstractString
    url::AbstractString
    function Fred(key, url)
        # Key validation
        if length(key) > API_KEY_LENGTH
            key = key[1:API_KEY_LENGTH]
            warn("FRED API key too long. First $(API_KEY_LENGTH) chars used.")
        elseif length(key) < API_KEY_LENGTH
            error("Invalid FRED API key -- key too short: $(key)")
        end
        if !all(isxdigit, key)
            error("Invalid FRED API key -- invalid characters: $(key)")
        end
        return new(key, url)
    end
end
Fred(key::AbstractString) = Fred(key, DEFAULT_API_URL)
function Fred()
    key = if KEY_ENV_NAME in keys(ENV)
        ENV[KEY_ENV_NAME]
    elseif isfile(joinpath(homedir(), KEY_FILE_NAME))
        open(joinpath(homedir(), KEY_FILE_NAME), "r") do file
            rstrip(read(file, String))
        end
    else
        error("FRED API Key not detected.")
    end

    println("API key loaded.")
    return Fred(key)
end
get_api_key(f::Fred) = f.key
get_api_url(f::Fred) = f.url
set_api_url!(f::Fred, url::AbstractString) = setfield!(f, :url, url)

function Base.show(io::IO, f::Fred)
    @printf io "FRED API Connection\n"
    @printf io "\turl: %s\n" get_api_url(f)
    @printf io "\tkey: %s\n" get_api_key(f)
end


"""
```
FredSeries(...)
```
Represent a single data series, and all associated metadata, as queried from FRED.
The following fields are available:
- `id`
- `title`
- `units_short`
- `units`
- `seas_adj_short`
- `seas_adj`
- `freq_short`
- `freq`
- `realtime_start`
- `realtime_end`
- `last_updated`
- `notes`
- `trans_short`
- `data`
"""
struct FredSeries
    # From series query
    id::AbstractString
    title::AbstractString
    units_short::AbstractString
    units::AbstractString
    seas_adj_short::AbstractString
    seas_adj::AbstractString
    freq_short::AbstractString
    freq::AbstractString
    realtime_start::AbstractString
    realtime_end::AbstractString
    last_updated::DateTime
    notes::AbstractString

    # From series/observations query
    trans_short::AbstractString # "units"
    data::DataFrames.DataFrame

    # deprecated
    df::DataFrames.DataFrame
end

function Base.show(io::IO, s::FredSeries)
    @printf io "FredSeries\n"
    @printf io "\tid: %s\n"                s.id
    @printf io "\ttitle: %s\n"             s.title
    @printf io "\tunits: %s\n"             s.units
    @printf io "\tseas_adj (native): %s\n" s.seas_adj
    @printf io "\tfreq (native): %s\n"     s.freq
    @printf io "\trealtime_start: %s\n"    s.realtime_start
    @printf io "\trealtime_end: %s\n"      s.realtime_end
    @printf io "\tlast_updated: %s\n"      s.last_updated
    @printf io "\tnotes: %s\n"             s.notes
    @printf io "\ttrans_short: %s\n"       s.trans_short
    @printf io "\tdata: %dx%d DataFrame with columns %s\n" size(s.data)... names(s.data)
end

# old, deprecated accessors
export
    id, title, units_short, units, seas_adj_short, seas_adj, freq_short,
    freq, realtime_start, realtime_end, last_updated, notes, trans_short,
    df
@deprecate id(f::FredSeries) getfield(f, :id)
@deprecate title(f::FredSeries) getfield(f, :title)
@deprecate units_short(f::FredSeries) getfield(f, :units_short)
@deprecate units(f::FredSeries) getfield(f, :units)
@deprecate seas_adj_short(f::FredSeries) getfield(f, :seas_adj_short)
@deprecate seas_adj(f::FredSeries) getfield(f, :seas_adj)
@deprecate freq_short(f::FredSeries) getfield(f, :freq_short)
@deprecate freq(f::FredSeries) getfield(f, :freq)
@deprecate realtime_start(f::FredSeries) getfield(f, :realtime_start)
@deprecate realtime_end(f::FredSeries) getfield(f, :realtime_end)
@deprecate last_updated(f::FredSeries) getfield(f, :last_updated)
@deprecate notes(f::FredSeries) getfield(f, :notes)
@deprecate trans_short(f::FredSeries) getfield(f, :trans_short)
@deprecate df(f::FredSeries) getfield(f, :data)

function get_data(f::Fred, series::AbstractString; kwargs...)
    # Validation
    validate_args!(kwargs)

    # Setup
    metadata_url = get_api_url(f) * "series"
    obs_url      = get_api_url(f) * "series/observations"
    api_key      = get_api_key(f)

    # Add query parameters
    metadata_params = Dict("api_key"   => api_key,
                           "file_type" => "json",
                           "series_id" => series)
    obs_params = copy(metadata_params)

    # Query observations. Expand query dict with kwargs. Do this first so we can use the
    # calculated realtime values for the metadata request.
    for (key, value) in kwargs
        obs_params[string(key)] = string(value)
    end
    obs_response = HTTP.request("GET", obs_url, []; query=obs_params)
    obs_json = JSON.parse(String(copy(obs_response.body)))

    # Parse observations
    realtime_start  = obs_json["realtime_start"]
    realtime_end    = obs_json["realtime_end"]
    transformation_short = obs_json["units"]

    df = parse_observations(obs_json["observations"])

    # Query metadata
    metadata_params["realtime_start"] = realtime_start
    metadata_params["realtime_end"] = realtime_end
    metadata_response = HTTP.request("GET", metadata_url, []; query=metadata_params)
    metadata_json = JSON.parse(String(copy(metadata_response.body)))
    # TODO catch StatusError and just return incomplete data to the caller

    # Parse metadata
    metadata_parsed = Dict{Symbol, AbstractString}()
    for k in ["id", "title", "units_short", "units", "seasonal_adjustment_short",
        "seasonal_adjustment", "frequency_short", "frequency", "notes"]
        try
            metadata_parsed[Symbol(k)] = metadata_json["seriess"][1][k]
        catch err
            metadata_parsed[Symbol(k)] = ""
            @warn "Metadata '$k' not returned from server."
        end
    end

    # the last three chars are -05, for CST in St. Louis
    function parse_last_updated(last_updated)
        timezone = last_updated[end-2:end]  # TODO
        return DateTime(last_updated[1:end-3], "yyyy-mm-dd HH:MM:SS")
    end
    last_updated = parse_last_updated(
        metadata_json["seriess"][1]["last_updated"])

    # format notes field
    metadata_parsed[:notes] = strip(replace(replace(
        metadata_parsed[:notes], r"[\r\n]" => " "), r" +" => " "))

    return FredSeries(metadata_parsed[:id], metadata_parsed[:title],
                      metadata_parsed[:units_short], metadata_parsed[:units],
                      metadata_parsed[:seasonal_adjustment_short],
                      metadata_parsed[:seasonal_adjustment],
                      metadata_parsed[:frequency_short], metadata_parsed[:frequency],
                      realtime_start, realtime_end, last_updated, metadata_parsed[:notes],
                      transformation_short, df,
                      df) # deprecated
end

# obs is a vector, of which each element is a dict with four fields,
# - realtime_start
# - realtime_end
# - date
# - value
function parse_observations(obs::Vector)
    n_obs = length(obs)
    value = Vector{Float64}(undef, n_obs)
    date  = Vector{Date}(undef, n_obs)
    realtime_start = Vector{Date}(undef, n_obs)
    realtime_end = Vector{Date}(undef, n_obs)
    for (i, x) in enumerate(obs)
        try
            value[i] = parse(Float64, x["value"])
        catch err
            value[i] = NaN
        end
        date[i]           = Date(x["date"], "yyyy-mm-dd")
        realtime_start[i] = Date(x["realtime_start"], "yyyy-mm-dd")
        realtime_end[i]   = Date(x["realtime_end"], "yyyy-mm-dd")
    end
    return DataFrame(realtime_start=realtime_start, realtime_end=realtime_end,
                     date=date, value=value)
end

isyyyymmdd(x) = occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)
function validate_args!(kwargs)
    d = Dict(kwargs)

    # dates
    for k in [:realtime_start, :realtime_end, :observation_start, :observation_end]
        if (v = pop!(d, k, nothing)) != nothing && !isyyyymmdd(v)
                error("$k: Invalid date format: $v")
        end
    end
    # limit and offset
    for k in [:limit, :offset]
        if (v = pop!(d, k, nothing)) != nothing &&
            ( !(typeof(v) <: Number ) || typeof(v) <: Number && !(v>0) )
                error("$k: Invalid format: $v")
        end
    end
    # units
    if (v = pop!(d, :units, nothing)) != nothing &&
        v ∉ ["lin", "chg", "ch1", "pch", "pc1", "pca", "cch", "log"]
            error("units: Invalid format: $v")
    end
    # frequency
    if (v = pop!(d, :frequency, nothing)) != nothing &&
        v ∉ ["d", "w", "bw", "m", "q", "sa", "a", "wef", "weth", "wew", "wetu", "wem",
             "wesu", "wesa", "bwew", "bwem"]
            error("frequency: Invalid format: $v")
    end
    # aggregation_method
    if (v = pop!(d, :aggregation_method, nothing)) != nothing &&
        v ∉ ["avg", "sum", "eop"]
            error("aggregation_method: Invalid format: $v")
    end
    # output_type
    if (v = pop!(d, :output_type, nothing)) != nothing &&
        v ∉ [1, 2, 3, 4]
            error("output_type: Invalid format: $v")
    end
    # vintage dates, and too early vintages
    if (v = pop!(d, :vintage_dates, nothing)) != nothing
        vds_arr = split(string(v), ",")
        vds_bad = map(x -> !isyyyymmdd(x), vds_arr)
        if any(vds_bad)
            error("vintage_dates: Invalid date format: $(vds_arr[vds_bad])")
        end
        vds_early = map(x -> x<EARLY_VINTAGE_DATE, vds_arr)
        if any(vds_early)
            warn(:vintage_dates, ": Early vintage date, data might not exist: ",
                vds_arr[vds_early])
        end
    end
    # all remaining keys have unspecified behavior
    if length(d) > 0
        for k in keys(d)
            warn(string(k), ": Bad key. Removed from query.")
            deleteat!(kwargs, findall(x -> x[1]==k, kwargs))
        end
    end
end

############################################
############################################

f = Fred("266c597cbf3d25f366b082b4bf5161fe")
function log_diff(x::DataFrame)
    temp = zeros(length(x[:,1]))
    for i in 1:length(x[:,1])
        temp[i] = log(x[i,2])
    end
    diff_array = diff(temp)
    for i in 1:length(x[:,1])-1
        x[i,2] = diff_array[i]
    end
    x[length(x[:,1]),2] = NaN
    x[:,2] = replace(x[:,2], NaN => missing)
    return x
end

function diff_ts(x::DataFrame)
    temp = zeros(length(x[:,1]))
    for i in 1:length(x[:,1])
        temp[i] = x[i,2]
    end
    diff_array = diff(temp)
    for i in 1:length(x[:,1])-1
        x[i,2] = diff_array[i]
    end
    x[length(x[:,1]),2] = NaN
    x[:,2] = replace(x[:,2], NaN => missing)
    return x
end

function log_diff_diff(x::DataFrame)
    temp = zeros(length(x[:,1]))
    for i in 1:length(x[:,1])
        temp[i] = log(x[i,2])
    end
    diff_array = diff(diff(temp))
    for i in 1:length(x[:,1])-2
        x[i,2] = diff_array[i]
    end
    x[length(x[:,1])-1,2] = NaN
    x[length(x[:,1]),2] = NaN
    x[:,2] = replace(x[:,2], NaN => missing)
    return x
end

function log_ts(x::DataFrame)
    for i in 1:length(x[:,1])
        x[i,2] = log(x[i,2])
    end
    return x
end

#############################################
#############################################
test_quarterly = CSV.read("current_2.csv")

### Transform data
GDPC1 = get_data(f, "GDPC1").data[:, [3,4]]
GDPC1 = log_diff(GDPC1)
symbol = Symbol("GDPC1")
rename!(GDPC1, :value => symbol)

GDPCTPI = get_data(f, "GDPCTPI").data[:, [3,4]]
GDPCTPI = log_diff_diff(GDPCTPI)
symbol = Symbol("GDPCTPI")
rename!(GDPCTPI, :value => symbol)

function transform_data(x::String, y::Int64)
    Tcode = y

    df = get_data(Fred("266c597cbf3d25f366b082b4bf5161fe"), x).data[:, [3,4]]

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

    return df
end

### Import dateset

test_monthly = CSV.read("current.csv", header = false)
code_series = test_monthly[[1,2],:]

### Format the datetime object
dformat = Dates.DateFormat("m/d/y")
date = test_monthly[:,1]

temp = Array{Union{Missing, Date}}(missing, 1)
temp = [temp
    [missing]]
for i in 3:length(date)
    if ismissing(date[i])
        temp = [temp
            [missing]]
        break
    end
    temp = [temp
        [Dates.Date.(date[i], dformat)]]
end

test_monthly[:,1] = temp
rename!(test_monthly, :Column1 => :date)

### Change Mnemonics
code_series[1,5] = "CMRMTSPL"
code_series[1,6] = "RETAIL"
code_series[1,21] = "M0882BUSM350NNBR" #Help-wanted index ?
code_series[1,22] = "M08335USM499NNBR" #Help-wanted unemploy ?
code_series[1,32] = "ICSA" #initial claim
code_series[1,60] = "DGORDER" #New Orders for DUrable Goods?
code_series[1,61] = "NEWORDER" #New Orders for Nondefense Capital Goods?
code_series[1,62] = "AMDMUO"
code_series[1,63] = "BUSINV"
code_series[1,64] = "ISRATIO"
code_series[1,74] = "FLNONREVSL" # Nonrevolving consumer credit to Personal Income ?
code_series[1,75] = "SP500"
code_series[1,76] = "DJIA" # ??? S&P industrial average the same with Dow Jone?
code_series[1,77] = "QPEN368BIS" # Series DNE, but I just put a random series to keep going?
code_series[1,78] = "QPER628BIS" # Series DNE again!?
code_series[1,80] = "CP3M"
code_series[1,88] = "CPFF"
code_series[1,97] = "EXSZUS"
code_series[1,98] = "EXJPUS"
code_series[1,99] = "EXUSUK"
code_series[1,100] = "EXCAUS"
code_series[1,105] = "OILPRICE"
code_series[1,124] = "UMCSENT"
code_series[1,129] = "VXOCLS"



### Creating new dataset
initial = test_monthly[:,[1,2]]

for i in 2:35
    println(code_series[1,i], " ", i)
    df_1 = transform_data(code_series[1, i], parse(Int64, code_series[2,i]))
    initial = join(initial, df_1, on = :date, kind = :left)
end

for i in 36:70
    println(code_series[1,i], " ", i)
    df_1 = transform_data(code_series[1, i], parse(Int64, code_series[2,i]))
    initial = join(initial, df_1, on = :date, kind = :left)
end

for i in 71:105
    println(code_series[1,i], " ", i)
    df_1 = transform_data(code_series[1, i], parse(Int64, code_series[2,i]))
    initial = join(initial, df_1, on = :date, kind = :left)
end

for i in 106:length(test_monthly[1,:])
    println(code_series[1,i], " ", i)
    df_1 = transform_data(code_series[1, i], parse(Int64, code_series[2,i]))
    initial = join(initial, df_1, on = :date, kind = :left)
end

final = initial[3:end,:]
final = deletecols!(final, 2)
final = join(final, GDPC1, on = :date, kind = :left)
final = join(final, GDPCTPI, on = :date, kind = :left)

CSV.write("epic_matrix.csv", final, writeheader = true)
