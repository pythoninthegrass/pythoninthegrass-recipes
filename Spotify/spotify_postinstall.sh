#!/usr/bin/env bash

# SOURCES
# https://gist.github.com/hjuutilainen/dc6e8b77af0dced03271ef1a10471cb0
# https://github.com/autopkg/recipes/blob/master/Spotify/Spotify.munki.recipe#L38-L46
# https://gist.github.com/iJunkie22/94569f41186df962f272
# https://www.launchd.info/
# https://github.com/jamf/MakeMeAnAdmin
# https://www.splinter.com.au/using-launchd-to-run-a-script-every-5-mins-on/
# https://superuser.com/questions/126907/how-can-i-get-a-script-to-run-every-day-on-mac-os-x
# https://stackoverflow.com/questions/50025049/trying-to-understand-launchd-daemon-state
# https://apple.stackexchange.com/questions/365782/how-can-i-use-home-or-in-my-log-paths-of-launchd-plist-to-run-as-launchagent
# https://github.com/grnhse/Rx/tree/master/spotify_postinstall

# activate verbose standard output (stdout)
set -v
# activate debugging (execution shown)
set -x

spotify_path="/Applications/Spotify.app"

if [[ ! -d "${spotify_path}" ]]; then
    echo "File not found: ${spotify_path}"
    exit 1
fi

if [[ ! -z $(pgrep -f Spotify) ]]; then
    echo 'Closing Spotify '
    pkill -15 'Spotify'
fi

# Find every file executable by its owner
echo "Fixing Spotify permissions "
IFS=$'\n'
for executable in $(find "${spotify_path}" -perm -u=x -type f); do
    permissions=$(stat -f "%Op" "${executable}")
    if [[ ${permissions} != "100755" ]]; then
        chmod 755 "${executable}"
    fi
done

chmod -R go+rX "${spotify_path}"

# Remove hidden update folder (suppress update prompt)
sp_update=$(find /private/var/folders -type d -name "sp_update" 2> /dev/null)

if [[ ! -z "$sp_update" ]]; then
    echo "Removing $sp_update "
    rm -rf "$sp_update"
else
   echo "Spotify update directory not found "
fi

# TODO: `elif` to grep/diff and update PLIST + SH accordingly
if [[ ! -e '/Library/Application Support/JAMF/remove_sp_update.sh' ]]; then
    # heredoc for the launch daemon to run to demote the user back and then pull logs of what the user did.
    cat << 'EOF' > '/Library/Application Support/JAMF/remove_sp_update.sh'
#!/bin/bash

sp_update=$(find /private/var/folders -type d -name "sp_update" 2> /dev/null)

if [[ -e "${sp_update}" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Removed ${sp_update} "
    rm -rf "$sp_update"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') Spotify update directory not found "
fi

# Disabled LaunchDaemon removal; running weekly is ideal
# launchctl unload '/Library/LaunchDaemons/remove_sp_update.plist'
# rm '/Library/LaunchDaemons/remove_sp_update.plist'
# rm /tmp/remove_sp_update.stdout.log
# rm /tmp/remove_sp_update.error.log
EOF
else
    echo 'remove_sp_update.sh already exists '
fi

# Write a daemon that will let you remove the sp_update directory with another script and chmod/chown to make sure it'll run, then load the daemon
if [[ ! -e '/Library/LaunchDaemons/remove_sp_update.plist' ]]; then
    # Create the plist
    defaults write /Library/LaunchDaemons/remove_sp_update.plist Label -string "remove_sp_update"

    # TODO: QA `--foreground` argument
    # Add program argument to get a process ID, then run the update script
    # defaults write /Library/LaunchDaemons/remove_sp_update.plist ProgramArguments -array -string "--foreground" \
    # -string /bin/bash -string "/Library/Application Support/JAMF/remove_sp_update.sh"
    defaults write /Library/LaunchDaemons/remove_sp_update.plist ProgramArguments -array -string /bin/bash -string "/Library/Application Support/JAMF/remove_sp_update.sh"

    # Set the run interval to every 5 days
    # defaults write /Library/LaunchDaemons/remove_sp_update.plist StartInterval -integer 300 # 5 minutes to test
    defaults write /Library/LaunchDaemons/remove_sp_update.plist StartInterval -integer 432000

    # Set run at load
    defaults write /Library/LaunchDaemons/remove_sp_update.plist RunAtLoad -boolean yes

    # DISABLE POST-QA
    # Logging
    # defaults write /Library/LaunchDaemons/remove_sp_update.plist StandardOutPath /tmp/remove_sp_update.stdout.log
    # defaults write /Library/LaunchDaemons/remove_sp_update.plist StandardErrorPath /tmp/remove_sp_update.error.log

    # Set ownership
    chown root:wheel /Library/LaunchDaemons/remove_sp_update.plist
    chmod 644 /Library/LaunchDaemons/remove_sp_update.plist

    # Load the daemon
    launchctl load /Library/LaunchDaemons/remove_sp_update.plist
    echo "$(date '+%Y-%m-%d %H:%M:%S') LaunchDaemon created" > '/tmp/remove_sp_update.stdout.log'
    sleep 10
else
    echo 'remove_sp_update.plist already exists '
fi

# Debug launchdaemon (root)
# plutil -lint /Library/LaunchDaemons/remove_sp_update.plist
# defaults read /Library/LaunchDaemons/remove_sp_update.plist
# launchctl error <78>  # 78: malformed array (e.g., `--foreground` passed _after_ shell script)
# launchctl list | grep sp_update
# tail -f /tmp/remove_sp_update.stdout.log
# tail -f /tmp/remove_sp_update.error.log
# tail -F /var/log/system.log | grep --line-buffered "com.apple.launchd\[" | grep "remove_sp_update.plist"

# Re-open Spotify
open $spotify_path

# deactivate verbose and debugging stdout
set +v
set +x

unset IFS

exit 0