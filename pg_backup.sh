#!/bin/bash
# ******************************************************************************************************* #
#                                                                                                         #
# 2024-11-10   ridonekorkmaz    PostgreSQL 17 has incremental backup feature.                             #
#                               However every incremental backup contains changes from last full backup.  #
#                               This increases volume of change over time.                                #
#                               It is possible to apply changes to full backup and use it as a reference  #
#                               for the next incremental backup to overcome this challenge.               #
#                               In this case it is possible to backup only changes from last              #
#                               incremental backup. This script implements this use-case.                 #
#                                                                                                         #
# ******************************************************************************************************* #
#
PATH_PREFIX="/mnt/pg_backups"
FULL_BACKUP="${PATH_PREFIX}/full"
INCR_BACKUP="${PATH_PREFIX}/incremental"
ROLLFW_PATH="${PATH_PREFIX}/rollfw"
# get opts
for i in "$@"; do
  case $i in
    -m=*|--mode=*)
      MODE="${i#*=}"
      shift
      ;;
    -*|--*)
      echo "Unknown option $i"
      echo "Usage:"
      echo "  ${0} --mode=<full | incremental>"
      exit 1
      ;;
    *)
      ;;
  esac
done

if [ "${MODE}" == "full" ]
then
  psql -qc "checkpoint"
  mkdir -p ${FULL_BACKUP} && chmod 0700 ${FULL_BACKUP}
  pg_basebackup --checkpoint=fast -D ${FULL_BACKUP}
elif [ "${MODE}" == "incremental" ]
then
  mkdir -p ${INCR_BACKUP}
  psql -qc "checkpoint"
  # check if any incremental backup exists
  if [ -z "$( ls -A ${INCR_BACKUP} )" ]
  then
    # first incremental, skip pg_combinebackup
    pg_basebackup --checkpoint=fast --incremental=${FULL_BACKUP}/backup_manifest -D ${INCR_BACKUP}
  else
    # nth incremental, run pg_combinebackup then pg_basebackup
    mkdir -p ${ROLLFW_PATH} && chmod 0700 ${ROLLFW_PATH}
    pg_combinebackup --clone -o ${ROLLFW_PATH} ${FULL_BACKUP} ${INCR_BACKUP}
    rm -rf ${FULL_BACKUP} ${INCR_BACKUP}
    mkdir -p ${INCR_BACKUP}
    mv ${ROLLFW_PATH} ${FULL_BACKUP}
    pg_basebackup --checkpoint=fast --incremental=${FULL_BACKUP}/backup_manifest -D ${INCR_BACKUP}
  fi
fi
