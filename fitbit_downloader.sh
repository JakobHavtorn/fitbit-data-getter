# Authorization token
AUTH="Authorization: Bearer <INSERT AUTHORIZATION HERE>"

# Start and end dates
D0="2017-05-06"   # Inclusive
D1="2018-06-04"   # Exclusive

# Method for performing a count down for a duration in minutes
countdown() {
  echo -n "Sleeping for ${1} minutes"
  echo ""
  for ((i=$1;i>=1;i--)); do
    echo "$i minutes remaining..."
    sleep 1m
  done
}

# Method for monitoring the number of requests made to server and pause if maximum is exceeded
# Input the file last written to
# 1. From bottom find the first line reading
#    Fitbit-Rate-Limit-Remaining: REQUESTS_REMAINING
# 2. If REQUESTS_REMAINING is zero
#       Read the line immediately below
#       Fitbit-Rate-Limit-Reset: SECONDS_UNTIL_RESET
#       Count down for this duration in seconds
# 3. If REQUESTS_REMAINING smaller than zero
#    pass
WAS_PAUSED=0
maybe_pause() {
  REQUESTS_REMAINING=$(tac $1 | grep -m 1 'Fitbit-Rate-Limit-Remaining' | cut -f2 -d' ')
  REQUESTS_REMAINING=${REQUESTS_REMAINING//[ $'\001'-$'\037']}  # Remove trailing newline
  echo "$REQUESTS_REMAINING requests remaining"
  if [[ $REQUESTS_REMAINING == 0 ]]
  then
    SECONDS_UNTIL_RESET=$(tac $1 | grep -m 1 'Fitbit-Rate-Limit-Reset' | cut -f2 -d' ')
    SECONDS_UNTIL_RESET=${SECONDS_UNTIL_RESET//[ $'\001'-$'\037']}  # Remove trailing newline
    MINUTES_UNTIL_RESET=$(((SECONDS_UNTIL_RESET+59)/60 + 1))
    echo ""
    echo "Maximum number of requests per hour reached."
    echo "$SECONDS_UNTIL_RESET seconds until reset"
    echo "$MINUTES_UNTIL_RESET minutes until reset"
    echo ""
    countdown $MINUTES_UNTIL_RESET
    WAS_PAUSED=1
  else
    WAS_PAUSED=0
  fi
}

# Helper method to get date in the YYYY-MM-DD format from a string.
# Also supports adding like "+ 1 day"
get_date () {
    date +%Y-%m-%d --date "$1"
}

# Helper method that iterates over all days in a range and requests intra-day 
# statistics for the input activity type for each entire day
get_intraday_range() {
  D0_ITER=$D0
  while [[ $D0_ITER != $D1 ]]; do
    echo "$D0_ITER"
    curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$1/date/$D0_ITER/1d/1min/time/00:00/23:59.json >> $1-intra-daily.json
    sed -i -e '$a\' $1-intra-daily.json
    # Pause
    maybe_pause $1-intra-daily.json
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 0 ]]
    then
      D0_ITER=$(get_date "$D0_ITER + 1 day")
    fi
  done
}

# Method to download intra-day statistics for a list of activities
get_intradays() {
  echo "========== INTRA-DAY =========="
  echo ""
  for activity in "${INTRA_ACTIVITIES[@]}"
  do
    echo "$activity" | awk '{print toupper($0)}'
    get_intraday_range $activity
    echo ""
  done
  echo ""
  echo ""
}

# Method to request daily statistics (e.g. total number of steps) 
# for a list of activities
get_dailys() {
  echo "========== DAILIES =========="
  echo ""
  for activity in "${DAILY_ACTIVITIES[@]}"
  do
    echo "$activity" | awk '{print toupper($0)}'
    curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$activity/date/$D0/$D1.json >> $activity-daily.json
    echo ""
    # Pause
    maybe_pause $1-intra-daily.json
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 1 ]]
    then
      curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$activity/date/$D0/$D1.json >> $activity-daily.json
    fi
    sed -i -e '$a\' $activity-daily.json
  done
  echo "SLEEP"
  curl -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$D0/$D1.json >> sleep-daily.json
  # Pause
  maybe_pause $1-intra-daily.json
  # Check if execution was pause: If it was, then retry last request
  if [[ $WAS_PAUSED == 1 ]]
  then
    curl -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$D0/$D1.json >> sleep-daily.json
  fi
  echo ""
  echo ""
}

# Method to get user profile
get_profile() {
  echo "========== PROFILE =========="
  echo ""
  curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/profile.json > profile.json
  echo ""
  maybe_pause profile.json
  echo ""
}

# Daily activities
declare -a DAILY_ACTIVITIES=(
  calories
  caloriesBMR
  steps
  distance
  floors
  elevation
  minutesSedentary
  minutesLightlyActive
  minutesFairlyActive
  minutesVeryActive
  activityCalories
)

# Intra-day activities
declare -a INTRA_ACTIVITIES=(
  heart
  calories
  steps
  distance
  floors
  elevation
)

# Get statistics
get_profile
get_intradays
get_dailys


# Profile



# Steps [daily],
# echo "========== DAILY ACTIVITIES =========="
# echo ""
# curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/steps/date/$D0/$D1.json > steps-daily.json
# echo ""
# echo ""
# echo "========================================================"
# echo ""
# echo ""


# get_intradays "heart"
# echo ""
# echo ""
# echo "========================================================"
# echo ""
# echo ""



# # Loop over dates
# while [[ $D0 != $D1 ]]; do
#   D0=$(get_date "$D0 + 1 day")
#   echo "$D0"
# done

# echo $AUTH




# Sleep
# https://api.fitbit.com/1.2/user/[user-id]/sleep/date/[startDate]/[endDate].json



# Heart rate
# curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/heart/date/2017-05-12/1d/1min/time/00:00/23:59.json > heartrate-intra-day.json
# echo "\n\n####################################################\n\n"




# Types of data
# - Daily summary
# - Time series (daily)
# - Time series (intra-day)


# # Activity time series
# https://api.fitbit.com/1/user/-/[resource-path]/date/[base-date]/[end-date].json
# activities/calories
# activities/caloriesBMR
# activities/steps
# activities/distance
# activities/floors
# activities/elevation
# activities/minutesSedentary
# activities/minutesLightlyActive
# activities/minutesFairlyActive
# activities/minutesVeryActive
# activities/activityCalories

# # Heart rate
# curl -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/heart/date/[date]/1d/[detail-level].json


# Resources
# https://dev.fitbit.com/build/reference/web-api/heart-rate/
# https://dev.fitbit.com/build/reference/web-api/activity/
# https://dev.fitbit.com/apps
# https://annofoneblog.wordpress.com/2017/10/19/your-heart-your-calories-your-sleep-your-data-how-to-extract-your-fitbit-data-and-make-graphs-using-r/
