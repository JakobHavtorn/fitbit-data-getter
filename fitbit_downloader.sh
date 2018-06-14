# TODO Fix daily sleep download (max 100 day range)

# Stop on error
set -e

# ============================================================================ #
# ============================== INPUT SECTION ============================== #
# ============================================================================ #

# Start and end dates
D0="2017-05-06"   # Inclusive
D1="2018-06-09"   # Exclusive

# What to get
GET_DAILY_STATISTICS=false     # This will overwrite already downloaded daily statistics in DATA_FOLDER
GET_INTRADAY_STATISTICS=false  # This creates new files for each day and will correctly add to existing data
GET_SLEEP_STATISTICS=false      # This will overwrite already downloaded data in the DATA_FOLDER
GET_ACTIVITY_STATISTICS=true   # This will overwrite already downloaded data in the DATA_FOLDER
CREATE_CSVS=false              # Creates .csv files from .json files using Python (importable in Health)

# Data folders
DATA_FOLDER="data"            # Folder to place downloaded data into
OLD_DATA_FOLDER="data-old"    # Folder into which data already in ${DATA_FOLDER} is moved before starting download
IMPORT_FOLDER="data-import"   # Folder into which ${DATA_FOLDER} is copied after download has finished.
                              # New runs don't overwrite this until they are succesfully completed.
                              # This folder is used to create .csv files and for importing to Health

# Daily activities
declare -a DAY_ACTIVITIES=(
  calories
  caloriesBMR
  steps
  distance
  floors
  elevation
  heart
  minutesSedentary
  minutesLightlyActive
  minutesFairlyActive
  minutesVeryActive
  activityCalories
)

# Intra-day activities
declare -a INTRADAY_ACTIVITIES=(
  heart
  calories
  steps
  distance
  floors
  elevation
)


# ============================================================================ #
# ============================== METHODS SECTION ============================== #
# ============================================================================ #

# Method to define date and tac commands for MacOS
define_aliases() {
  if [[ "$OSTYPE" == "darwin"* ]]
  then
    date() { gdate "$@"; }
    tac() { tail -r -- "$@"; }
  fi
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
# statistics for the input activity type for each entire day.
# Will not redownload already downloaded days
get_intraday_single_activity() {
  D0_ITER=$D0
  # Iterate over days between D0 and D1
  while [[ $D0_ITER != $D1 ]]; do
    OUT="${DATA_FOLDER}/intraday/${1}/${D0_ITER}.json"
    echo -n "${OUT} | "    
    # Only download if not already downloaded
    if [ ! -f ${OUT} ]; then
      curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/${1}/date/${D0_ITER}/1d/1min/time/00:00/23:59.json > ${OUT}
      maybe_pause ${OUT}
      # Check if execution was pause: If it was, then retry last request since this errors out
      if [[ ${WAS_PAUSED} == 0 ]]
      then
        D0_ITER=$(get_date "${D0_ITER} + 1 day")
      fi
    else
      # File already downloaded, increment to next day
      echo "Already downlaoded"
      D0_ITER=$(get_date "${D0_ITER} + 1 day")
    fi
  done
}

# Method to download intra-day statistics for a list of activities
get_intradays() {
  echo ""
  echo "========== INTRA-DAY =========="
  echo ""
  for activity in "${INTRADAY_ACTIVITIES[@]}"
  do
    echo "${activity}" | awk '{print toupper($0)}'
    get_intraday_single_activity ${activity}
    echo ""
  done
}

# Method to request daily statistics (e.g. total number of steps) 
# for a list of activities
get_dailys() {
  echo ""  
  echo "========== DAILIES =========="
  echo ""
  for activity in "${DAY_ACTIVITIES[@]}"
  do
    OUT="${DATA_FOLDER}/day/${activity}.json"
    # echo - n "${activity}" | awk '{print toupper($0)}'
    echo -n "$OUT | "
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/${activity}/date/$D0/$D1.json > ${OUT}
    # Pause
    maybe_pause $OUT
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 1 ]]
    then
      curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/${activity}/date/$D0/$D1.json > ${OUT}
    fi
  done
}


days_between() {
  echo "( `date -d $2 +%s` - `date -d $1 +%s`) / (24*3600)" | bc -l
}


# Method for getting sleep data
# Note that we can only request 100 days of sleep data at a time, so we have to loop
get_sleep() {
  echo ""  
  echo "========== SLEEP =========="
  echo ""
  Di=${D0}
  Dj=$(get_date "${Di} + 100 day")
  REM_DAYS=$(days_between ${Di} ${D1})
  while [[ $REM_DAYS > 0 ]]; do
    echo "${Di} to ${Dj}"
    curl -s -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$Di/$Dj.json > ${DATA_FOLDER}/day/sleep-${Di}-${Dj}.json
    # Pause
    maybe_pause ${DATA_FOLDER}/day/sleep-${Di}-${Dj}.json
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 1 ]]
    then
      curl -s -i -H "$AUTH" https://api.fitbit.com/1.2/user/-/sleep/date/$Di/$Dj.json > ${DATA_FOLDER}/day/sleep-${Di}-${Dj}.json
    fi
    # Next 100 day range (if not REM_DAYS <= 0)
    Di=$(get_date "${Di} + 100 day")
    Dj=$(get_date "${Dj} + 100 day")
    REM_DAYS=$(days_between ${Di} ${D1})
  done
}

get_activities() {
  echo ""  
  echo "========== ACTIVITIES =========="
  echo ""
  Di=${D0}
  REM_DAYS=$(days_between ${Di} ${D1})
  while [[ $REM_DAYS > 0 ]]; do
    Dj=$(get_date "${Di} + 20 day") # 
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/list.json?limit=20&sort=asc&offset=0&afterDate=${Di}T00:00:00.000Z > ${DATA_FOLDER}/day/activities-${Di}-${Dj}.json
    maybe_pause $OUT
    # Check if execution was pause: If it was, then retry last request
    if [[ $WAS_PAUSED == 1 ]]
    then
      curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/activities/list.json?limit=20&sort=asc&offset=0&afterDate=${Di}T00:00:00.000Z > ${DATA_FOLDER}/day/activities-${Di}-${Dj}.json
    fi
    Di=${Dj}
    REM_DAYS=$(days_between ${Di} ${D1})
  done
}

# Method to get user profile
get_profile() {
  echo ""
  echo "========== PROFILE =========="
  echo ""
  curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/profile.json > ${DATA_FOLDER}/profile.json
  maybe_pause ${DATA_FOLDER}/profile.json
  if [[ $WAS_PAUSED == 1 ]]
  then
    curl -s -i -H "$AUTH" https://api.fitbit.com/1/user/-/profile.json > ${DATA_FOLDER}/profile.json
  fi
}

# Method that creates the directories, DATA_FOLDER, OLD_DATA_FOLDER and IMPORT_FOLDER
make_dirs() {
  # Intra daily data directories (subfolder for each directory)
  for activity in "${INTRADAY_ACTIVITIES[@]}"
  do
    if [[ ! -d ${DATA_FOLDER}/intraday/${activity} ]]
    then
      mkdir -p -v ${DATA_FOLDER}/intraday/${activity}
    fi
  done
  # Daily directory (only if not exists)
  if [[ ! -d ${DATA_FOLDER}/day ]]
  then
    mkdir -p -v ${DATA_FOLDER}/day
  fi
  # Old data directory (overwrite previous)
  # rm -r $OLD_DATA_FOLDER
  # mkdir -p -v $OLD_DATA_FOLDER
}

# Method to copy data folder to another folder given as input
copy_data () {
  echo ""
  echo "Creating copy of ./${DATA_FOLDER} in ./${1}..."
  cp -r ./${DATA_FOLDER}/ ./${1}
}

# ============================================================================ #
# ============================== SCRIPT SECTION ============================== #
# ============================================================================ #

# Start message
echo ""
echo "Downloading Fitbit data"
echo "Start date:           ${D0} (inclusive)"
echo "End date:             ${D1} (exclusive)"
echo "Daily statistics:     ${GET_DAILY_STATISTICS}"
echo "Intraday statistics:  ${GET_INTRADAY_STATISTICS}"
echo "Sleep statistics:     ${GET_SLEEP_STATISTICS}"
echo "Activity statistics:  ${GET_ACTIVITY_STATISTICS}"
echo "Create CSV files:     ${CREATE_CSVS}"
echo ""
read -p "Proceed? (y/n) " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

# Authorization token
source authorization.token

# Make directories
make_dirs

# Make copy of previously downloaded data
# copy_data $OLD_DATA_FOLDER

# Define special methods
define_aliases

# Get profile
get_profile

# Get statistics
if [ "$GET_DAILY_STATISTICS" = true ] ; then
  get_dailys
fi
if [ "$GET_INTRADAY_STATISTICS" = true ] ; then
  get_intradays
fi
if [ "$GET_SLEEP_STATISTICS" = true ] ; then
  get_sleep
fi
if [ "$GET_ACTIVITY_STATISTICS" = true ] ; then
  get_activities
fi

# Copy to data-import
# rm -r $IMPORT_FOLDER
# mkdir -p -v $IMPORT_FOLDER
# copy_data $IMPORT_FOLDER

# Create csvs
if [ "$CREATE_CSVS" = true ] ; then
  echo "Creating .csv files using python..."
  echo ""
  python create_csvs.py
fi

# End
echo ""
echo ""
echo "Download ended succesfully"
exit 0
