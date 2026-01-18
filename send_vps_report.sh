#!/bin/bash

# --- CONFIGURATION ---
EMAIL_TO="vitalya.dev@gmail.com"
HISTORY_FILE="/var/log/openvpn-history.csv"

# 1. Fetch IP once to use in both Subject and Image
VPS_IP=$(curl -4 -s ifconfig.me)
SUBJECT="VPS $VPS_IP Daily Traffic Report"

# Temporary file paths
IMG_SUMMARY="/tmp/vps_summary.png"
IMG_DAILY="/tmp/vps_daily.png"
IMG_HOURLY="/tmp/vps_hourly.png"
IMG_COMBINED="/tmp/vps_combined.png"

# --- GENERATE IMAGES ---
# Generate the standard vnstati graphs (runs on Host)
/usr/bin/vnstati -L -s -o $IMG_SUMMARY
/usr/bin/vnstati -L -d -o $IMG_DAILY
/usr/bin/vnstati -L -hg -o $IMG_HOURLY

# --- DOCKER IMAGE MAGIC ---
# Stack images and annotate with IP
docker run --rm --entrypoint magick -v /tmp:/tmp dpokidov/imagemagick \
    $IMG_SUMMARY $IMG_DAILY $IMG_HOURLY -append \
    -gravity NorthEast -pointsize 20 -fill red -annotate +20+20 "VPS: $VPS_IP" \
    $IMG_COMBINED

# --- GENERATE VPN TEXT REPORT (FROM HISTORY) ---
VPN_REPORT=$(
    if [ -f "$HISTORY_FILE" ]; then
        # Check if file has data (more than just header)
        line_count=$(wc -l < "$HISTORY_FILE")

        if [ "$line_count" -gt 1 ]; then
            # Header with new columns
            printf "%-16s | %-10s | %-15s | %-15s | %s\n" "IP ADDRESS" "TRAFFIC" "COUNTRY" "CITY" "ISP"
            echo "--------------------------------------------------------------------------------------"

            # Parse CSV: Sum (Rx + Tx) per IP ($3)
            # We pipe the sorted list into a loop to handle the API calls
            awk -F, 'NR>1 { sum[$3] += $4 + $5 } END { for (ip in sum) print sum[ip], ip }' "$HISTORY_FILE" | \
            sort -nr | \
            while read bytes ip; do
                # 1. Convert bytes to human readable
                human_bytes=$(numfmt --to=iec-i --suffix=B "$bytes")

                # 2. Fetch Geo Data (Country, City, ISP)
                # using ip-api.com (csv format for easy parsing)
                geo_data=$(curl -s "http://ip-api.com/csv/${ip}?fields=country,city,isp")

                # Check if curl failed or returned empty
                if [ -z "$geo_data" ]; then
                     geo_data="Unknown,Unknown,Unknown"
                fi

                # Parse the CSV response (handling spaces usually requires care,
                # but ip-api csv is simple: Country,City,ISP)
                IFS=',' read -r country city isp <<< "$geo_data"

                # 3. Print the formatted line
                printf "%-16s | %-10s | %-15s | %-15s | %s\n" "$ip" "$human_bytes" "${country:0:14}" "${city:0:14}" "$isp"

                # 4. Rate Limit (Important: 45 req/min limit)
                sleep 1.5
            done
        fi
    fi
)

# If report is empty (no history file or no lines), set default
if [ -z "$VPN_REPORT" ]; then
    VPN_REPORT="No traffic recorded in history logs for today."
fi

# --- SEND EMAIL ---
# We attach only the $IMG_COMBINED file
echo -e "Attached is the combined traffic graph for today.\n\n=== OpenVPN Daily Usage ===\n\n$VPN_REPORT" | \
/usr/bin/mutt -s "$SUBJECT" -a $IMG_COMBINED -- $EMAIL_TO

# --- CLEANUP ---
rm $IMG_SUMMARY $IMG_DAILY $IMG_HOURLY $IMG_COMBINED
