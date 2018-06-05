# Stop on error
set -e

# Start and end dates
D0="2017-05-06"   # Inclusive
D1="2018-06-04"   # Exclusive

# Data folders
DATA_FOLDER="data"            # Folder to place downloaded data into
OLD_DATA_FOLDER="data-old"    # Folder into which data already in $DATA_FOLDER is moved before starting download
BACKUP_FOLDER="backup"        # Folder into which $DATA_FOLDER is copied after download has finished

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

# Method to define date and tac commands for MacOS
define_aliases() {
  if [[ "$OSTYPE" == "darwin"* ]]
  then
    date() { gdate "$@"; }
    tac() { tail -r -- "$@"; }
  fi

  # if [[ "$OSTYPE" == "linux-gnu" ]]
  # then
  #   # ...
  # elif [[ "$OSTYPE" == "darwin"* ]]
  # then
  #   # Mac OSX
  #   alias date='gdate'
  # elif [[ "$OSTYPE" == "cygwin" ]]
  # then
  #   # POSIX compatibility layer and Linux environment emulation for Windows
  # elif [[ "$OSTYPE" == "msys" ]]
  # then
  #   # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
  # elif [[ "$OSTYPE" == "win32" ]]
  # then
  #   # I'm not sure this can happen.
  # elif [[ "$OSTYPE" == "freebsd"* ]]
  # then
  #   # ...
  # else
  #   # Unknown.
  # fi
}

# Method for performing a count down for a duration in minutes
countdown() {
  echo -n "Sleeping for ${1} minutes"
  echo ""
  for ((i=$1;i>=1;i--)); do
    echo "$i minutes remaining..."
    sleep 60
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
    echo "$SECONDS_UNTIL_RESET seconds / $MINUTES_UNTIL_RESET minutes until reset"
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
    echo -n "$D0_ITER | "
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$1/date/$D0_ITER/1d/1min/time/00:00/23:59.json >> $DATA_FOLDER/$1-intra-daily.json
    sed -i -e '$a\' $DATA_FOLDER/$1-intra-daily.json
    # Pause
    maybe_pause $DATA_FOLDER/$1-intra-daily.json
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
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$activity/date/$D0/$D1.json >> $DATA_FOLDER/$activity-daily.json
    echo ""
    # Pause
    maybe_pause $DATA_FOLDER/$1-intra-daily.json
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 1 ]]
    then
      curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/$activity/date/$D0/$D1.json >> $DATA_FOLDER/$activity-daily.json
    fi
    sed -i -e '$a\' $DATA_FOLDER/$activity-daily.json
  done
  echo "SLEEP"
  curl -s -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$D0/$D1.json >> $DATA_FOLDER/sleep-daily.json
  # Pause
  maybe_pause $DATA_FOLDER/$1-intra-daily.json
  # Check if execution was pause: If it was, then retry last request
  if [[ $WAS_PAUSED == 1 ]]
  then
    curl -s -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$D0/$D1.json >> $DATA_FOLDER/sleep-daily.json
  fi
  echo ""
  echo ""
}

# Method to get user profile
get_profile() {
  echo "========== PROFILE =========="
  echo ""
  curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/profile.json > $DATA_FOLDER/profile.json
  maybe_pause $DATA_FOLDER/profile.json
  echo ""
  if [[ $WAS_PAUSED == 1 ]]
  then
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/profile.json > $DATA_FOLDER/profile.json
  fi
}

# Authorization token
source authorization.token

# Make directory for new data (if not exists)
if [[ ! -d $DATA_FOLDER ]]
then
  mkdir -p -v $DATA_FOLDER
fi
# Make directory for old data (if not exists)
if [[ ! -d $OLD_DATA_FOLDER ]]
then
  mkdir -p -v $OLD_DATA_FOLDER
fi
# Copy old data to old data folder
echo "Create copy of already downloaded data in ./$DATA_FOLDER"
cp -r -v ./$DATA_FOLDER/ ./$OLD_DATA_FOLDER
echo ""

# Define special methods
define_aliases
# Get profile
get_profile
# Get statistics
get_intradays
get_dailys

# Create backup of newly downloaded data
if [[ ! -d $BACKUP_FOLDER ]]
then
  mkdir -p -v $BACKUP_FOLDER
fi
echo "Create a backup of the newly downloaded data"
cp -r -v ./$DATA_FOLDER/ ./$BACKUP_FOLDER
echo ""

# Steps [daily],
# echo "========== DAILY ACTIVITIES =========="
# echo ""
# curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/steps/date/$D0/$D1.json > steps-daily.json
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
# curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/heart/date/2017-05-12/1d/1min/time/00:00/23:59.json > heartrate-intra-day.json
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
# curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/heart/date/[date]/1d/[detail-level].json


# Resources
# https://dev.fitbit.com/build/reference/web-api/heart-rate/
# https://dev.fitbit.com/build/reference/web-api/activity/
# https://dev.fitbit.com/apps
# https://annofoneblog.wordpress.com/2017/10/19/your-heart-your-calories-your-sleep-your-data-how-to-extract-your-fitbit-data-and-make-graphs-using-r/
# https://towardsdatascience.com/collect-your-own-fitbit-data-with-python-ff145fa10873