library(tidyverse)
library(fredr)
library(reshape2)
library(readxl)
library(lubridate)
library(readr)
library(purrr)
library(httr)


seriescodes <- read_csv("fred_mnemonics_tcodes_and_blocks.csv")




fredr_set_key("266c597cbf3d25f366b082b4bf5161fe")

startdate = as.Date("1959-01-01")
enddate = as.Date("2020-01-31")

params <-list(
  series_id = seriescodes$fredcode,
  frequency = "m",
  observation_start = startdate,
  observation_end = enddate
)


#check for missing series
# this is hacky -- basically, when it breaks, jj is the index of the data it's breaking on.  Also a good way to get rate limited!
# for (jj in 1:nrow(seriescodes)){
#   jj
#   series_id = seriescodes$fredcode[jj]
#   fredr_request(endpoint = "series", series_id =series_id, to_frame = FALSE)
# }

# not robust to missing series, unfortunately


# tryCatch()
#   
#   
#   
#   
fred_out <- pmap_dfr(
  .l = params,
  .f = ~ fredr(series_id = ..1, frequency = ..2, observation_start = ..3, observation_end = ..4)
)

q_seriescodes = data.frame(fredcode = c('GDPC1','GDPDEF'), transform = c(1,1), block = c('Q','Q'))

params_q <-list(
  series_id = c('GDPC1','GDPDEF'),
  frequency = "q",
  observation_start = startdate,
  observation_end = enddate,
  units = "cch"
)


fred_out_q <- pmap_dfr(
  .l = params_q,
  .f = ~ fredr(series_id = ..1, frequency = ..2, observation_start = ..3, observation_end = ..4, units = ..5)
)

fred_out_q <- fred_out_q %>% 
  mutate(date = add_with_rollback(date, months(2))) %>% 
  mutate(value = value/100)

fred_out <- rbind(fred_out,fred_out_q)

dataout <- fred_out %>% 
  pivot_wider(names_from = series_id)

dataout_ts <- ts(dataout)

dataout_new <- dataout

for (jj in 1:nrow(seriescodes)){
  tcode<- seriescodes$transform[jj]
  dataout_new[,jj+1] = case_when(
    tcode == 1 ~ as.numeric(dataout_ts[,jj+1]),
    tcode == 2 ~ as.numeric(c(NaN, diff(dataout_ts[,jj+1]))),
    tcode == 3 ~ as.numeric(c(NaN, NaN, diff(diff(dataout_ts[,jj+1])))),
    tcode == 4 ~ as.numeric(log(dataout_ts[,jj+1])),
    tcode == 5 ~ as.numeric(c(NaN, diff(log(dataout_ts[,jj+1])))),
    tcode == 6 ~ as.numeric( c(NaN, NaN, diff(diff(log(dataout_ts[,jj+1]))))),
    tcode == 7 ~ as.numeric(c(NaN, NaN, diff( (dataout_ts[2:nrow(dataout),jj+1]- dataout_ts[1:nrow(dataout)-1,jj+1])/dataout_ts[1:nrow(dataout)-1,jj+1]))),
    TRUE ~ NaN 
  )
}

dataout_new <- dataout_new %>%  pivot_longer(cols = -date) %>% 
  group_by(name) %>%
  mutate(value = value - mean(value, na.rm = TRUE)) %>% 
  ungroup() %>% 
  pivot_wider()

  

# export this vintage
datestr <- as.character(today())

datavintage <- paste("dfm_data_vintage_", datestr,".csv", sep="")
write.csv(dataout_new,datavintage)
