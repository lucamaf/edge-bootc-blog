import requests
import subprocess
import json
import time
import csv
import os
import sys
import fcntl

# Function to parse the std output from pmprobe denki
# first item denki submetric
# second item number of metrics
# third item package value
# fourth item core value
# fifth item uncore value
# sixth item dram value
def parse_pmprobe_output(output):
    # Assuming the output is in a specific format, you can customize this function
    parsed_data = {}
    metrics = output.split()
    parsed_data["package"]=metrics[2]
    parsed_data["core"]=metrics[3]
    parsed_data["uncore"]=metrics[4]
    parsed_data["dram"]=metrics[5]
    return parsed_data

# Function to read the CSV file and return its contents
def read_csv(file_path):
    with open(file_path, mode='r') as file:
        reader = csv.reader(file)
        return [row for row in reader]
        #return reader

def prep_data(data):
    pretty_data = json.loads(data)
    return json.dumps(pretty_data, indent=2)

# command to be executed to obtain file output to csv file
# $ script -q -c "pmrep -H -f '' -t 5s -o csv denki.rapl" /dev/null | tee power.csv
# command to probe sensors and get accumulated values
# pmprobe -v denki.rapl
# Function to send data to the REST API
def send_to_api(data, api_url):
    headers = {'Content-Type': 'application/json'}
    response = requests.post(api_url, headers=headers, data=data)
    if response.status_code == 200:
        print("Data sent successfully:", response.json())
    else:
        print("Failed to send data. Status Code:", response.status_code)

# Main function to run the program
if __name__ == "__main__":
    csv_file_path = 'power.csv'  # Replace with your CSV file path
    last_size = 0
    
    #cmd = 'pmrep -H -t 5s -o csv denki.rapl'
    api_url = 'http://localhost:4318/v1/metrics'  # otel collector rest api
    #with subprocess.Popen(['pmrep', '-H', '-t', '5s', '-o', 'csv', 'denki.rapl'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as p:
        # Make stdout non-blocking when using read/readline
        #p_stdout = p.stdout
        #fl = fcntl.fcntl(p_stdout, fcntl.F_GETFL)
        #fcntl.fcntl(p_stdout, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    while True:
        time.sleep(5)
        result = subprocess.run(['pmprobe', '-v', 'denki.rapl'], stdout=subprocess.PIPE)
        values = parse_pmprobe_output(result.stdout.decode('utf-8'))

        print(values)
        now=str(int(time.time()))
        json_data = '{ "resourceMetrics":'\
        '[{ "resource": { "attributes":'\
        '[{ "key": "system","value": {"stringValue": "package"}}]},'\
        '"scopeMetrics": [{ "metrics": ['\
        '{"name": "core.cpu.power","unit": "W","description": "","gauge": {"dataPoints": ['\
        '{"asDouble": '+values["core"]+',"timeUnixNano": "'+now+'000000000"}]}},'\
        '{"name": "uncore.gpu.power","unit": "W","description": "","gauge": {"dataPoints": ['\
        '{"asDouble": '+values["uncore"]+',"timeUnixNano": "'+now+'000000000"}]}},'\
        '{"name": "dram.memory.power","unit": "W","description": "","gauge": {"dataPoints": ['\
        '{"asDouble": '+values["dram"]+',"timeUnixNano": "'+now+'000000000"}]}}]}]}]}'
        send_to_api(prep_data(json_data), api_url)

        # CSV logic
        #current_size = os.path.getsize(csv_file_path)
        #if current_size > last_size:  # Check if the file has been updated
            #last_size = current_size
            # return one csv row
            #data = read_csv(csv_file_path)[-1]
            #core=str(data[2])
            #uncore=str(data[3])
            #dram=str(data[4])
            #now=str(int(time.time()))
            #json_data = '{ "resourceMetrics":'\
            #'[{ "resource": { "attributes":'\
            #'[{ "key": "system","value": {"stringValue": "package"}}]},'\
            #'"scopeMetrics": [{ "metrics": ['\
            #'{"name": "core.cpu.power","unit": "W","description": "","gauge": {"dataPoints": ['\
            #'{"asDouble": '+core+',"timeUnixNano": "'+now+'000000000"}]}},'\
            #'{"name": "uncore.gpu.power","unit": "W","description": "","gauge": {"dataPoints": ['\
            #'{"asDouble": '+uncore+',"timeUnixNano": "'+now+'000000000"}]}},'\
            #'{"name": "dram.memory.power","unit": "W","description": "","gauge": {"dataPoints": ['\
            #'{"asDouble": '+dram+',"timeUnixNano": "'+now+'000000000"}]}}]}]}]}'

            #print(prep_data(json_data))
            #send_to_api(prep_data(json_data), api_url)

            #time.sleep(3)  # shorter delay than pmrep query
