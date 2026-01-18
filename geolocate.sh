#!/bin/bash

# Check if an input file was provided
if [ -z "$1" ]; then
    echo "Usage: ./geolocate.sh <filename>"
    exit 1
fi

echo "Processing IPs from $1..."
echo "---------------------------------------------------"
printf "%-16s | %-20s | %-20s | %s\n" "IP Address" "Country" "City" "ISP"
echo "---------------------------------------------------"

# 1. 'awk' extracts just the first column (the IP)
# 2. Loop through each IP
awk '{print $1}' "$1" | while read -r ip; do

    # Skip empty lines
    if [[ -n "$ip" ]]; then
        # Fetch data from ip-api.com in CSV format for easy parsing
        # Fields requested: country, city, isp
        response=$(curl -s "http://ip-api.com/csv/${ip}?fields=country,city,isp")

        # Replace commas with pipes for cleaner output alignment
        formatted_response=$(echo "$response" | sed 's/,/ | /g')

        # Print the result
        printf "%-16s | %s\n" "$ip" "$formatted_response"

        # IMPORTANT: ip-api.com has a rate limit of 45 requests per minute.
        # We sleep for 1.5 seconds to ensure we don't get banned.
        sleep 1.5
    fi

done
