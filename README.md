# -- Log Export Script for Check Point logging modules --
Syntax: log_export.sh [-v | --verbose]

- Setup: SERVER, USER and KEYFILE variables need populating
- Designed to run as background job
- Tests connection to remote server and lists directory to prevent duplicate creation
- Use verbose flag and script log file for debugging
- $FWDIR/log path, *.log* file names
- Read file ages from filename timestamps
- Filenames must be timestamped YYYY-MM-DD, and be within this century
- Consider files whose timestamp month value are older than one month ago
- Compress eligible files to archive file for that month, COMP-YYYYMM
- Each local archive is deleted after transfer to allow for low disk space
- No plain-text password used. Relies on authorised-key authentication
- No FW-1 log deletion is performed by this script
- Further work: getopts handling, and accepting opts for one-time use

# -- Procedure --
```
Variables
Grab "*.log*" directory list to array
Declare functions, set vars by input flag

Put break in script's log file
loop, check each file
  Exit if no files, skip if no timestamp
  Check it's over a month ago
  Add eligible file to array, creating array named YYYYMM if it doesn't exist
  Add new array name "YYYYMM" to a separate array for later referencing
end loop

Test server connection and retrieve directory list, exit if it fails
If archives exist in remote list, remove those names from process
Exit if there are no new archives to process

Create temporary directory
loop month archives for compression
  Compress all files of the same month to tarball
  If compressed, scp archive with key authentication and no password
  delete archive file
end loop
Delete temporary directory
```
