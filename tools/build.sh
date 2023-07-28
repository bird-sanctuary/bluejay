#!/bin/bash
source_path=$(dirname $(pwd))

usage() {
  echo "Usage: $0 [-l <A-W>] [-m <X|H|L>] [-d <integer>] [-p <24|48|96>] [-s <version string>] [-c <custom settings dir path>]" 1>&2
  exit 1
}

while getopts ":l:m:d:p:s:c:" o; do
  case "${o}" in
    l)
      layout=${OPTARG}
      ;;
    m)
      mcu=${OPTARG}
      ((mcu == "X" || mcu == "H" || mcu == "L")) || usage
      ;;
    d)
      deadtime=${OPTARG}
      ;;
    p)
      pwm=${OPTARG}
      ((pwm == 24 || pwm == 48 || pwm == 96)) || usage
      ;;
    s)
      version=${OPTARG}
      ;;
    c)
      settingsdir=${OPTARG}
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${layout}" ] && [ -z "${mcu}" ] && [ -z "${deadtime}" ] && [ -z "${pwm}" ]; then
  # All optional parameters are missing
  target="all"
  params="all"
else
  if [ -z "${layout}" ] || [ -z "${mcu}" ] || [ -z "${deadtime}" ] || [ -z "${pwm}" ]; then
    # If one optional parameter is given, all are needed
    usage
  fi

  target="${layout}_${mcu}_${deadtime}_${pwm}"
  params="LAYOUT=${layout} MCU=${mcu} DEADTIME=${deadtime} PWM=${pwm}"
fi

if [ -n "${version}" ]; then
  params="${params} VERSION=${version}"
fi

if [ -n "${settingsdir}" ]; then
  params="${params} SETTINGSDIR=${settingsdir}"
fi

echo "Building ${target}"

docker run -t -d --name bluejay-$target --mount type=bind,source="$source_path",target=/root/source bluejay-build:latest
docker exec bluejay-$target sh -c "cd /root/source && make $params"
docker stop bluejay-$target > /dev/null
docker rm bluejay-$target > /dev/null
