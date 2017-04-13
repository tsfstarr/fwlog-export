#!/bin/bash
source /etc/profile.d/CP.sh             # Check Point env vars
EXPORTLOG='/var/log/log_export.log'
SERVER=''
USER=''
KEYFILE=
RDIR=''
DIR='/var/tmp/log_export'
FILES=$FWDIR/log/*.log*
COMPDIRS=()
MONTH=$(date +%m)
YEAR=$(date +%Y)
VERBOSE=1
RDIRFAIL=0

#----------- SETUP

is_verbose () {                         # Echo argument if verbosity enabled
  if [[ $VERBOSE = 0 ]]; then
    echo "$1"
  fi
}

containsElement () {                    # Check element exists in array
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

is_oldlog () {                          # Check if log is older than one month
  local IN="$(echo $1 | awk -F/ '{print $NF}')"
  IFS='-' read -r -a LOGTIME <<< "$IN"  # Read filename
  LOGTIME[1]="10#${LOGTIME[1]}"         # Force month value with leading zero from octal to decimal

  #If log year is lower and it's not a comparison of (Dec,YY and Jan,YY+1), or log month of same year is older than 1 month
  if (( (${LOGTIME[1]} < $(($MONTH-1))) && (${LOGTIME[0]} == $YEAR) )); then   # Same year
    return 0
  elif (( ${LOGTIME[0]} < $YEAR )); then                                       # Lower year
    if (( ($MONTH == 1) && (${LOGTIME[1]} == 12) && (${LOGTIME[0]} == $(($YEAR-1))) )); then
      return 1
    else
      return 0
    fi
  else                                  # Catch all including weird timestamps
    return 1
  fi
}

compress () {                           # Compress month of filenames
  is_verbose "Compressing $1..."
  gtar -zcvf "$DIR/$1.tgz" $2 >> $EXPORTLOG 2>&1                       
  if [ "$?" -eq "0" ]; then
	return 0
  else
    is_verbose "$(echo "Compression failed for $1..." | tee -a $EXPORTLOG)"
	return 1
  fi
}

transfer () {                           # Transfer file by SFTP
  is_verbose "Transferring $1..."
  if [ "$RDIRFAIL" -gt "0" ]; then      # If RDIR was not accessible in the listing phase, do not try to change directory
    printf '%s\n' "lcd $DIR" "put $1.tgz" | sftp -b - -o IdentityFile="$KEYFILE" -o PasswordAuthentication=no $USER@$SERVER > /dev/null 2>&1
  else
    printf '%s\n' "lcd $DIR" "cd $RDIR" "put $1.tgz" | sftp -b - -o IdentityFile="$KEYFILE" -o PasswordAuthentication=no $USER@$SERVER > /dev/null 2>&1
  fi
  if [ "$?" -eq "0" ]; then
    is_verbose "$(echo "Successfully transferred $1." | tee -a $EXPORTLOG)"
	return 0
  else
    is_verbose "$(echo "Failed to transfer $1..." | tee -a $EXPORTLOG)"
	return 1
  fi
}

for arg in "$@"                         # Read script flags eg. verbosity
do
  case $arg in
    -v|--verbose)
      VERBOSE=0
      shift
    ;;
  esac
done

#------------ MAIN

is_verbose "Current date: Year $YEAR Month $MONTH"
echo "========================$(date)====================================" >> $EXPORTLOG
echo "Script executed by user: $(whoami)" >> $EXPORTLOG

for F in $FILES                         # Loop through "*.log" list
do
  if [ "$F" == "$FWDIR/log/*.log*" ]; then                                     # Exit with non-zero code if no file list
    is_verbose "$(echo "No logs found in \"\$FWDIR/log\"... exiting." | tee -a $EXPORTLOG)"
    exit 1
  fi
  if [[ ! $F =~ 20[0-9]{2} ]]; then     # Filename must reference a year within this century
    is_verbose "No timestamp in name. Skipping... [$F]"
    continue
  fi

  if is_oldlog $F; then                 # Do stuff for archive names array COMPDIRS
    COMP_REF="COMP_${LOGTIME[0]}${LOGTIME[1]:3:2}"                             # Reference relevant compression archive COMP_YYYYMM
    if ! containsElement "$COMP_REF" "${COMPDIRS[@]}"; then                    # compression archive not in COMPDIRS already
      COMPDIRS=("${COMPDIRS[@]}" "$COMP_REF")                                  # add to COMPDIRS
    fi
    if [ -z ${!COMP_REF+x} ]; then      # If unset, declare array of files for log archive COMP_YYYYMM
      declare -a $COMP_REF="$F"
    else                                # Array exists already, add to array of files
      eval $COMP_REF=\("\${$COMP_REF[@]}" "$F"\)
    fi
    is_verbose "!QUEUED FOR COMPRESSION!  [$F]   Log timestamp: ${LOGTIME[0]} ${LOGTIME[1]:3:2}"
  else
    is_verbose "Too recent or invalid time. Skipping... [$F]   Log timestamp: ${LOGTIME[0]} ${LOGTIME[1]:3:2}"
  fi
done
                                        # Test that remote directory exists
REMOTELIST=$(printf '%s\n' "cd $RDIR" "dir" | sftp -b - -o IdentityFile="$KEYFILE" -o PasswordAuthentication=no $USER@$SERVER)
if [ "$?" -gt "0" ]; then               # If remote directory cannot be accessed, do not try to change directory
  REMOTELIST=$(printf '%s\n' "dir" | sftp -b - -o IdentityFile="$KEYFILE" -o PasswordAuthentication=no $USER@$SERVER)
  RDIRFAIL=1
fi

if [ "$?" -gt "0" ]; then               # Exit if remote listing could not be retrieved
  is_verbose "$(echo "Remote server access failed. Exiting..." | tee -a $EXPORTLOG)"
  exit 1
fi
REMOTELIST=($REMOTELIST)                # Convert string to array
for REM in "${!REMOTELIST[@]}"; do      # Remove extensions
  REMOTELIST[REM]="${REMOTELIST[REM]%.*}"
done

COMPDIRS2=()
for D in "${COMPDIRS[@]}"; do           # Filter archive names that don't exist remotely into COMPDIRS2
  skip=
  for R in "${REMOTELIST[@]}"; do
      [[ $D == $R ]] && { skip=1; break; }
  done
  [[ -n $skip ]] || COMPDIRS2+=("$D")
done

if [ ${#COMPDIRS2[@]} -eq 0 -o -z "${COMPDIRS2[0]}" ]; then                    # Exit with non-zero code if no compression dirs
  is_verbose "$(echo "No new logs found in \"\$FWDIR/log\"... exiting." | tee -a $EXPORTLOG)"
  exit 1
fi

##### ENABLE WHEN TESTING #####
#echo "REMOTELIST: ${REMOTELIST[@]}"
#echo "COMPDIRS: ${COMPDIRS[@]}"
#echo "COMPDIRS2: ${COMPDIRS2[@]}"
#exit

is_verbose "Compression archive names: $(echo ${COMPDIRS2[@]})"
mkdir -v $DIR > /dev/null 2>&1  || is_verbose "$DIR exists already, or no permissions..."
for C in "${COMPDIRS2[@]}"              # Loop through compression archive names
do
  eval CARRAYSTR=\${$C[@]}              # String takes value of dynamic variable name
  compress "$C" "$CARRAYSTR" && transfer "$C"
  rm "$DIR/$C.tgz" > /dev/null 2>&1     # Delete archive in temp folder
done

is_verbose "$(echo "Deleting $DIR..." | tee -a $EXPORTLOG)"
rm -R $DIR
