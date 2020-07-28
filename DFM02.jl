# DFM02.jl

using LinearAlgebra, Statistics, Compat, HypothesisTests # Statistical analysis
using RDatasets, MultivariateStats # Principal Component Analysis
using Distributions, GLM # OLS
using DataFrames, CSV # Data analysis
using Dates, Plots #printf # Misc...

include("DFM_helpers.jl")

vintage = "dfm_data_vintage_2020-07-27"

data_in =DataFrame!(CSV.File("$vintage.csv"))

# Add in GDP data to the R file so that data_in includes it

# 
