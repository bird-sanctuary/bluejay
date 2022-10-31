#!/bin/bash
SOURCE_DIR=$1
TARGET_DIR=$2

FILES=$(ls $SOURCE_DIR)

TOTAL=0
MATCHING=0
EXISTING=0
DIFFERENT=0

for FILE in ${FILES}; do
  TOTAL=$((TOTAL+1))
  if [ -f "${TARGET_DIR}/${FILE}" ]; then
    EXISTING=$((EXISTING+1))
    diff ${SOURCE_DIR}/${FILE} ${TARGET_DIR}/${FILE} > files.diff
    if [ $? -eq 0 ]; then
      MATCHING=$((MATCHING+1))
    else
      DIFFERENT=$((DIFFERENT+1))
    fi
  fi
done

echo "Total files: ${TOTAL}; New files: $((TOTAL - EXISTING))"
if [ $MATCHING -eq $EXISTING ]; then
  echo "All existing files match!"
else
  echo Different: ${DIFFERENT}/${EXISTING}
fi
