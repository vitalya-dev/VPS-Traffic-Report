#!/bin/bash

# --- CONFIGURATION ---
EMAIL_TO="vtikerch@yandex.ru"
SUBJECT="VPS $(curl -4 -s ifconfig.me) Traffic Report"
# We point to the directory, not a specific file
LOG_PATTERN="/etc/openvpn/server/logs/*-status.log"

# Temporary file paths
IMG_SUMMARY="/tmp/vps_summary.png"
IMG_DAILY="/tmp/vps_daily.png"
IMG_HOURLY="/tmp/vps_hourly.png"
IMG_COMBINED="/tmp/vps_combined.png"

# --- GENERATE IMAGES ---
# Generate the standard vnstati graphs
/usr/bin/vnstati -L -s -o $IMG_SUMMARY
/usr/bin/vnstati -L -d -o $IMG_DAILY
/usr/bin/vnstati -L -hg -o $IMG_HOURLY

# --- IMAGE MAGIC (STITCHING) ---
# use convert with +append to join them horizontally
# (Use -append if you want them vertically stacked instead)
/usr/bin/convert $IMG_SUMMARY $IMG_DAILY $IMG_HOURLY +append $IMG_COMBINED

# --- GENERATE VPN TEXT REPORT ---
VPN_REPORT=$(awk -F, '
    FNR==1 { 
        n=split(FILENAME, a, "/"); 
        print "\n--- " a[n] " ---" 
    }
    /^CLIENT_LIST/ {
        run_time = systime() - $9;
        h = int(run_time/3600);  
        m = int((run_time%3600)/60);
        printf "%-25s Total: %6.2f MB   Duration: %dh %02dm\n", $3, ($6+$7)/1048576, h, m
    }
' $LOG_PATTERN)

# If report is empty, set default
if [ -z "$VPN_REPORT" ]; then
    VPN_REPORT="No active clients connected."
fi

# --- SEND EMAIL ---
# We now attach only the $IMG_COMBINED file
echo -e "Attached is the combined traffic graph for today.\n\n=== OpenVPN Active Clients ===$VPN_REPORT" | \
/usr/bin/mutt -s "$SUBJECT" -a $IMG_COMBINED -- $EMAIL_TO

# --- CLEANUP ---
rm $IMG_SUMMARY $IMG_DAILY $IMG_HOURLY $IMG_COMBINED