# DFM02.jl

using LinearAlgebra, Statistics, Compat, HypothesisTests # Statistical analysis
using RDatasets, MultivariateStats # Principal Component Analysis
using Distributions, GLM # OLS
using DataFrames, CSV # Data analysis
using Dates, Plots #printf # Misc...

vintage = "dfm_data_2020_07_27"

data_in = CSV.Read("$vintage.csv")
