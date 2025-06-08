#!/bin/bash
sleep 5
processor=$(lscpu --json | jq -r '.lscpu[8].data' | tr -d ' ' | sed -e 's/(R)//' -e 's/(TM)//')
while true
do
  sleep 5
  now=$(date +%s)
  temperature=$(cat /sys/class/thermal/thermal_zone0/temp)
  data=$(cat <<EOF
{
    "resourceMetrics": [
      {
        "resource": {
          "attributes": [
            {
              "key": "processor",
              "value": {"stringValue": "${processor}"}
            }
          ]
        },
        "scopeMetrics": [
          {
            "metrics": [
              {
                "name": "cpu.temp.degrees",
                "unit": "C",
                "description": "",
                "gauge": {
                  "dataPoints": [
                    {
                      "asInt": "${temperature}",
                      "timeUnixNano": "${now}000000000",
		                  "attributes":[ {"key": "processor", "value": {"stringValue": "${processor}"}} ]
                    }
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
}
EOF
)
  curl -X POST -H "Content-Type: application/json" -d "$data" localhost:4318/v1/metrics
done
