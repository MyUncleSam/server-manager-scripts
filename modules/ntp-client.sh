#!/bin/bash
#
# NTP Client Module
# Configure time synchronization using systemd-timesyncd
#

# Module metadata
module_info() {
    echo "NTP Client|Configure time synchronization and timezone"
}

# Configuration file
TIMESYNCD_CONF="/etc/systemd/timesyncd.conf"

# NTP Pool regions
declare -A NTP_POOLS=(
    ["global"]="pool.ntp.org"
    ["africa"]="africa.pool.ntp.org"
    ["asia"]="asia.pool.ntp.org"
    ["europe"]="europe.pool.ntp.org"
    ["north-america"]="north-america.pool.ntp.org"
    ["south-america"]="south-america.pool.ntp.org"
    ["oceania"]="oceania.pool.ntp.org"
)

# Country codes for NTP pools
declare -A NTP_COUNTRIES_EUROPE=(
    ["at"]="Austria"
    ["be"]="Belgium"
    ["bg"]="Bulgaria"
    ["ch"]="Switzerland"
    ["cz"]="Czech Republic"
    ["de"]="Germany"
    ["dk"]="Denmark"
    ["ee"]="Estonia"
    ["es"]="Spain"
    ["fi"]="Finland"
    ["fr"]="France"
    ["gb"]="United Kingdom"
    ["gr"]="Greece"
    ["hr"]="Croatia"
    ["hu"]="Hungary"
    ["ie"]="Ireland"
    ["it"]="Italy"
    ["lt"]="Lithuania"
    ["lu"]="Luxembourg"
    ["lv"]="Latvia"
    ["nl"]="Netherlands"
    ["no"]="Norway"
    ["pl"]="Poland"
    ["pt"]="Portugal"
    ["ro"]="Romania"
    ["rs"]="Serbia"
    ["ru"]="Russia"
    ["se"]="Sweden"
    ["si"]="Slovenia"
    ["sk"]="Slovakia"
    ["ua"]="Ukraine"
)

declare -A NTP_COUNTRIES_ASIA=(
    ["cn"]="China"
    ["hk"]="Hong Kong"
    ["id"]="Indonesia"
    ["il"]="Israel"
    ["in"]="India"
    ["ir"]="Iran"
    ["jp"]="Japan"
    ["kr"]="South Korea"
    ["my"]="Malaysia"
    ["ph"]="Philippines"
    ["pk"]="Pakistan"
    ["sg"]="Singapore"
    ["th"]="Thailand"
    ["tr"]="Turkey"
    ["tw"]="Taiwan"
    ["vn"]="Vietnam"
)

declare -A NTP_COUNTRIES_NORTH_AMERICA=(
    ["ca"]="Canada"
    ["mx"]="Mexico"
    ["us"]="United States"
)

declare -A NTP_COUNTRIES_SOUTH_AMERICA=(
    ["ar"]="Argentina"
    ["br"]="Brazil"
    ["cl"]="Chile"
    ["co"]="Colombia"
    ["ec"]="Ecuador"
    ["pe"]="Peru"
    ["uy"]="Uruguay"
    ["ve"]="Venezuela"
)

declare -A NTP_COUNTRIES_OCEANIA=(
    ["au"]="Australia"
    ["nz"]="New Zealand"
)

declare -A NTP_COUNTRIES_AFRICA=(
    ["za"]="South Africa"
    ["eg"]="Egypt"
    ["ma"]="Morocco"
    ["tz"]="Tanzania"
)

# Check if timesyncd is available
check_timesyncd() {
    if ! command_exists timedatectl; then
        ui_msgbox "Error" "timedatectl is not available on this system."
        return 1
    fi
    return 0
}

# Show current status
show_status() {
    if ! check_timesyncd; then
        return 1
    fi

    local info=""
    info+="=== Time Synchronization Status ===\n\n"

    # Get timedatectl status
    local status
    status=$(timedatectl status 2>&1)
    info+="$status\n\n"

    # Get current NTP servers
    if [[ -f "$TIMESYNCD_CONF" ]]; then
        info+="=== Configured NTP Servers ===\n\n"
        local servers
        servers=$(grep -E "^NTP=|^FallbackNTP=" "$TIMESYNCD_CONF" 2>/dev/null)
        if [[ -n "$servers" ]]; then
            info+="$servers\n"
        else
            info+="Using default servers\n"
        fi
    fi

    # Show timesyncd status
    info+="\n=== Service Status ===\n\n"
    local service_status
    service_status=$(systemctl status systemd-timesyncd --no-pager 2>&1 | head -20)
    info+="$service_status\n"

    echo -e "$info" > /tmp/ntp_status.txt
    ui_textbox "NTP Status" /tmp/ntp_status.txt
    rm -f /tmp/ntp_status.txt
}

# Select country from region
select_country_pool() {
    local region="$1"
    local -n countries_ref="$2"
    local region_pool="$3"

    # Build menu with region first, then countries
    local menu_items=()
    menu_items+=("region" "$region (entire region)")

    # Sort countries by name
    local sorted_codes
    sorted_codes=$(for code in "${!countries_ref[@]}"; do
        echo "$code ${countries_ref[$code]}"
    done | sort -k2 | awk '{print $1}')

    for code in $sorted_codes; do
        menu_items+=("$code" "${countries_ref[$code]}")
    done

    local choice
    choice=$(ui_menu "Select Pool" "Choose NTP pool:" "${menu_items[@]}") || return 1

    if [[ "$choice" == "region" ]]; then
        echo "0.$region_pool 1.$region_pool 2.$region_pool 3.$region_pool"
    else
        echo "0.$choice.pool.ntp.org 1.$choice.pool.ntp.org 2.$choice.pool.ntp.org 3.$choice.pool.ntp.org"
    fi
}

# Select NTP pool region
select_pool() {
    local choice
    choice=$(ui_menu "NTP Pool" "Select NTP pool type:" \
        "global" "Global pools" \
        "country" "Country-specific pools" \
        "custom" "Custom server") || return 1

    case "$choice" in
        global)
            local region
            region=$(ui_menu "Global Pool" "Select region:" \
                "global" "Global (pool.ntp.org)" \
                "africa" "Africa" \
                "asia" "Asia" \
                "europe" "Europe" \
                "north-america" "North America" \
                "south-america" "South America" \
                "oceania" "Oceania") || return 1

            local base_pool="${NTP_POOLS[$region]}"
            echo "0.$base_pool 1.$base_pool 2.$base_pool 3.$base_pool"
            ;;

        country)
            local region
            region=$(ui_menu "Select Region" "Choose region:" \
                "europe" "Europe" \
                "asia" "Asia" \
                "north-america" "North America" \
                "south-america" "South America" \
                "oceania" "Oceania" \
                "africa" "Africa") || return 1

            case "$region" in
                europe)
                    select_country_pool "Europe" NTP_COUNTRIES_EUROPE "europe.pool.ntp.org"
                    ;;
                asia)
                    select_country_pool "Asia" NTP_COUNTRIES_ASIA "asia.pool.ntp.org"
                    ;;
                north-america)
                    select_country_pool "North America" NTP_COUNTRIES_NORTH_AMERICA "north-america.pool.ntp.org"
                    ;;
                south-america)
                    select_country_pool "South America" NTP_COUNTRIES_SOUTH_AMERICA "south-america.pool.ntp.org"
                    ;;
                oceania)
                    select_country_pool "Oceania" NTP_COUNTRIES_OCEANIA "oceania.pool.ntp.org"
                    ;;
                africa)
                    select_country_pool "Africa" NTP_COUNTRIES_AFRICA "africa.pool.ntp.org"
                    ;;
            esac
            ;;

        custom)
            local custom_server
            custom_server=$(ui_inputbox "Custom NTP Server" "Enter NTP server address:") || return 1
            echo "$custom_server"
            ;;
    esac
}

# Select timezone
select_timezone() {
    # Get list of common timezones
    local tz_choice
    tz_choice=$(ui_menu "Timezone" "Select timezone region:" \
        "africa" "Africa" \
        "america" "America" \
        "asia" "Asia" \
        "atlantic" "Atlantic" \
        "australia" "Australia" \
        "europe" "Europe" \
        "indian" "Indian" \
        "pacific" "Pacific" \
        "utc" "UTC") || return 1

    if [[ "$tz_choice" == "utc" ]]; then
        echo "UTC"
        return 0
    fi

    # Get timezones for selected region
    local region="${tz_choice^}"  # Capitalize first letter
    local timezones
    timezones=$(timedatectl list-timezones | grep -i "^$region/" | sort)

    if [[ -z "$timezones" ]]; then
        ui_msgbox "Error" "No timezones found for region: $region"
        return 1
    fi

    # Build menu items
    local tz_list=()
    while IFS= read -r tz; do
        local city
        city=$(echo "$tz" | cut -d'/' -f2- | tr '_' ' ')
        tz_list+=("$tz" "$city")
    done <<< "$timezones"

    local selected_tz
    selected_tz=$(ui_menu "Select Timezone" "Choose timezone:" "${tz_list[@]}") || return 1

    echo "$selected_tz"
}

# Configure NTP servers
configure_ntp_servers() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    local servers
    servers=$(select_pool) || return

    if [[ -z "$servers" ]]; then
        return 1
    fi

    # Backup config
    if [[ -f "$TIMESYNCD_CONF" ]]; then
        backup_file "$TIMESYNCD_CONF"
    fi

    # Update configuration
    if [[ -f "$TIMESYNCD_CONF" ]]; then
        # Update existing NTP line or add it
        if grep -q "^NTP=" "$TIMESYNCD_CONF"; then
            sed -i "s|^NTP=.*|NTP=$servers|" "$TIMESYNCD_CONF"
        elif grep -q "^#NTP=" "$TIMESYNCD_CONF"; then
            sed -i "s|^#NTP=.*|NTP=$servers|" "$TIMESYNCD_CONF"
        else
            echo "NTP=$servers" >> "$TIMESYNCD_CONF"
        fi
    else
        # Create new config
        cat > "$TIMESYNCD_CONF" << EOF
[Time]
NTP=$servers
EOF
    fi

    # Restart timesyncd
    systemctl restart systemd-timesyncd

    log_info "NTP servers configured: $servers"
    ui_msgbox "Success" "NTP servers configured:\n\n$servers\n\nTime synchronization service restarted."
}

# Configure timezone
configure_timezone() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    local timezone
    timezone=$(select_timezone) || return

    if [[ -z "$timezone" ]]; then
        return 1
    fi

    # Set timezone
    if timedatectl set-timezone "$timezone"; then
        log_info "Timezone set to: $timezone"
        ui_msgbox "Success" "Timezone set to: $timezone"
    else
        ui_msgbox "Error" "Failed to set timezone"
    fi
}

# Enable NTP synchronization
enable_ntp() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    timedatectl set-ntp true
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd

    log_info "NTP synchronization enabled"
    ui_msgbox "Success" "NTP synchronization has been enabled."
}

# Disable NTP synchronization
disable_ntp() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    if ui_yesno "Disable NTP" "Are you sure you want to disable NTP synchronization?\n\nSystem time may drift without synchronization."; then
        timedatectl set-ntp false

        log_info "NTP synchronization disabled"
        ui_msgbox "Success" "NTP synchronization has been disabled."
    fi
}

# Force time sync
force_sync() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    ui_infobox "Syncing" "Forcing time synchronization..."

    # Restart timesyncd to force sync
    systemctl restart systemd-timesyncd
    sleep 2

    # Show sync status
    local status
    status=$(timedatectl timesync-status 2>&1 || timedatectl status 2>&1)

    log_info "Forced time synchronization"
    ui_msgbox "Sync Complete" "Time synchronization forced.\n\n$status"
}

# Quick setup
quick_setup() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    ui_msgbox "Quick Setup" "This will configure:\n\n1. NTP pool servers\n2. Timezone\n3. Enable time synchronization"

    # Select NTP pool
    local servers
    servers=$(select_pool) || return

    # Select timezone
    local timezone
    timezone=$(select_timezone) || return

    # Confirm settings
    if ! ui_yesno "Confirm Setup" "Apply these settings?\n\nNTP Servers:\n$servers\n\nTimezone: $timezone"; then
        return
    fi

    # Apply settings
    ui_infobox "Configuring" "Applying NTP configuration..."

    # Configure NTP servers
    if [[ -f "$TIMESYNCD_CONF" ]]; then
        backup_file "$TIMESYNCD_CONF"
    fi

    cat > "$TIMESYNCD_CONF" << EOF
[Time]
NTP=$servers
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org
EOF

    # Set timezone
    timedatectl set-timezone "$timezone"

    # Enable NTP
    timedatectl set-ntp true
    systemctl enable systemd-timesyncd
    systemctl restart systemd-timesyncd

    sleep 2

    log_info "Quick setup completed: NTP=$servers, TZ=$timezone"
    ui_msgbox "Setup Complete" "NTP client configured successfully!\n\nNTP Servers: $servers\nTimezone: $timezone\nSync: Enabled"
}

# Set time manually
set_time_manual() {
    if ! require_root; then
        return 1
    fi

    if ! check_timesyncd; then
        return 1
    fi

    # Check if NTP is enabled
    if timedatectl status | grep -q "NTP service: active"; then
        ui_msgbox "Warning" "NTP synchronization is currently enabled.\n\nDisable NTP first to set time manually."
        return
    fi

    local new_time
    new_time=$(ui_inputbox "Set Time" "Enter date and time (YYYY-MM-DD HH:MM:SS):" "$(date '+%Y-%m-%d %H:%M:%S')") || return

    if timedatectl set-time "$new_time"; then
        log_info "Time set manually to: $new_time"
        ui_msgbox "Success" "Time set to: $new_time"
    else
        ui_msgbox "Error" "Failed to set time.\n\nMake sure format is: YYYY-MM-DD HH:MM:SS"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "NTP Client" "Select operation:" \
            "quick" "Quick setup" \
            "status" "Show status" \
            "servers" "Configure NTP servers" \
            "timezone" "Configure timezone" \
            "enable" "Enable NTP sync" \
            "disable" "Disable NTP sync" \
            "sync" "Force time sync" \
            "manual" "Set time manually") || break

        case "$choice" in
            quick)    quick_setup ;;
            status)   show_status ;;
            servers)  configure_ntp_servers ;;
            timezone) configure_timezone ;;
            enable)   enable_ntp ;;
            disable)  disable_ntp ;;
            sync)     force_sync ;;
            manual)   set_time_manual ;;
        esac
    done
}
