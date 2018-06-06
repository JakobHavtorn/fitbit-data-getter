import json
import csv
import IPython
import os
import datetime


def flatten_json(json_dict, delim='.'):
    flat_json = {}
    for i in json_dict.keys():
        if isinstance(json_dict[i], dict):
            get = flatten_json(json_dict[i], delim)
            for j in get.keys():
                flat_json[i + delim + j] = get[j]
        else:
            flat_json[i] = json_dict[i]
    return flat_json


def read_json(jf):
    with open(jf, 'r') as f:
        # Discard junk at top
        for _ in range(16):
            next(f)
        # Load
        data = json.load(f)
    return data


def get_files(directory, ext="json"):
    files = []
    for f in os.listdir(directory):
        if f.endswith("." + ext):
            files.append(os.path.join(directory, f))
    return sorted(files)


def read_csv_as_dict(csv_file):
    try:
        with open(csv_file) as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                print(row['Row'], row['Name'], row['Country'])
    except IOError:
            raise IOError
            # print("I/O error({0}): {1}".format(errno, strerror))
    return


def write_dict_to_csv(csv_file, csv_column_names, list_of_dicts, mode='a', write_header=True):
    try:
        with open(csv_file, mode) as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=csv_column_names)
            if write_header:
                writer.writeheader()
            for data in list_of_dicts:
                writer.writerow(data)
    except IOError:
            raise IOError
            # print("I/O error({0}): {1}".format(errno, strerror))
    return


# def get_csv_column(activity):
#     """
#     List of units
#         ENTITY              UNIT
#         duration	        milliseconds
#         distance	        kilometers
#         elevation	        meters
#         height	            centimeters
#         weight	            kilograms
#         body measurements   centimeters
#         liquids	            milliliters
#         blood glucose	    millimoles per liter (mmol/dl) (molar concentration)
#     """
#     if activity == 'heart':
#         col = 'Heart rate [bpm]'
#     elif activity == 'calories':
#         col = 'Calories [cal]'
#     elif activity == 'steps':
#         col = 'Steps [#]'
#     elif activity == 'distance':
#         col = 'Distance [km]'
#     elif activity == 'floor':
#         col = 'Floors [#]'
#     elif activity == 'elevation':
#         col = 'Elevation [m]'
#     else:
#         raise ValueError("Unknown activity {}".format(activity))
#     return col


def create_intraday_csvs(**kwargs):
    # Data directory and activities
    intra_data_dir = kwargs.get('intra_data_dir', INTRADAY_DATA_DIR_DEFAULT)
    intra_activities = kwargs.get('intra_data_dir', INTRA_ACTIVITIES_DEFAULT)
    # Loop over activities
    for activity in intra_activities:
        activity_dir = os.path.join(intra_data_dir, activity)
        json_files = get_files(activity_dir)
        print(activity_dir)
        for i, jf in enumerate(json_files):
            # Read data
            data = read_json(jf)
            data = flatten_json(data)
            # Get the date of the intraday observations
            date = data['activities-' + activity][0]['dateTime']
            # Get the dataset
            intra_dataset = data['activities-' + activity + '-intraday.dataset']
            day_dataset = data['activities-' + activity]
            observation_interval = data['activities-' + activity + '-intraday.datasetInterval']
            observation_unit = data['activities-' + activity + '-intraday.datasetType']
            # Rename keys and prepend date (YYYY-MM-DD) to time
            Y, D, M = date.split('-')
            for obs in intra_dataset:
                obs['startTime'] = date + ' ' + obs.pop('time')
                obs[activity] = obs.pop('value')
                # Add end time for non-heart activities
                if activity != 'heart':
                    start = datetime.datetime.strptime(obs['startTime'], '%Y-%m-%d %H:%M:%S')
                    time_delta = {observation_unit + 's': observation_interval}
                    end = start + datetime.timedelta(**time_delta)
                    obs['endTime'] = end.strftime('%Y-%m-%d %H:%M:%S')

            # Write to csv
            out_file = os.path.join(intra_data_dir, activity + '.csv')
            column_names = list(obs.keys())
            write_header = i == 0
            mode = 'a' if i > 0 else 'w'
            write_dict_to_csv(out_file, column_names, intra_dataset, write_header=write_header, mode=mode)

            # Progress
            print(activity + ' | {}/{}'.format(i + 1, len(json_files)), end='\r')


def create_resting_heart_csv(**kwargs):
    # Data directory
    day_data_dir = kwargs.get('day_data_dir', DAY_DATA_DIR_DEFAULT)
    # Read file
    jf = os.path.join(day_data_dir, 'heart.json')
    data = read_json(jf)
    data = flatten_json(data)
    # Get data
    dataset = data['activities-heart']
    rhr_dataset = []
    for obs in dataset:
        try:
            rhr_obs = {'startTime': obs['dateTime'],
                       'restingHeartRate': obs['value']['restingHeartRate']}
            rhr_dataset.append(rhr_obs)
        except:
            pass
    # Write to .csv
    out_file = os.path.join(day_data_dir, 'restingHeart.csv')
    column_names = list(rhr_obs.keys())
    write_header = True
    mode = 'w'
    write_dict_to_csv(out_file, column_names, rhr_dataset, write_header=write_header, mode=mode)


def create_day_csvs(**kwargs):
    # Data directory and activities
    day_data_dir = kwargs.get('day_data_dir', DAY_DATA_DIR_DEFAULT)
    day_activities = kwargs.get('day_data_dir', DAY_ACTIVITIES_DEFAULT)

    json_files = get_files(day_data_dir)
    for jf in json_files:
        # Read data
        IPython.embed()
        data = read_json(jf)
        data = flatten_json(data)


DAY_DATA_DIR_DEFAULT = "data-import/day/"
DAY_ACTIVITIES_DEFAULT = {"calories",
                          "caloriesBMR",
                          "steps",
                          "distance",
                          "floors",
                          "elevation",
                          "minutesSedentary",
                          "minutesLightlyActive",
                          "minutesFairlyActive",
                          "minutesVeryActive",
                          "activityCalories"}
INTRADAY_DATA_DIR_DEFAULT = "data-import/intraday/"
INTRA_ACTIVITIES_DEFAULT = {"heart",
                            "calories",
                            "steps",
                            "distance",
                            "floors",
                            "elevation"}

create_resting_heart_csv()
create_intraday_csvs()
# create_day_csvs()
