# -------------------------------------------------------------------------------------------------#
# Filename:     cpuusage.py
# Author:       SAP AGS HANA DB Technology
# Date:         2015/01/08
# -------------------------------------------------------------------------------------------------#

# function: read_states - read the states of the indexserver proc
# params: core_cnt
# global: cpu_total_slice_A, cpu_total_slice_B
# read_states
#   read the start state of the indexserver process and write it into .fileA
#   sleep for 1 second
#   read the end state of the indexserver proc and write it into .fileB 
#
function read_states()
{
	core_cnt=$1

	for ((i=0; i<$core_cnt; i++))
	do cpu_total_slice_A[$i]=$(cat /proc/stat|grep "cpu$i"|awk '{for(i=2;i<=NF;i++)j+=$i;print j;}')
	done

	for file in /proc/$indexserver_pid/task/[0-9]*;
	do cat $file/stat;
	done > .fileA

	sleep 1 # sleep for 1 second

	for file in /proc/$indexserver_pid/task/[0-9]*;
	do cat $file/stat;
	done > .fileB

	for ((i=0; i<$core_cnt; i++))
	do cpu_total_slice_B[$i]=$(cat /proc/stat|grep "cpu$i"|awk '{for(i=2;i<=NF;i++)j+=$i;print j;}')
	done
}

# function: count_process_duration - accumulate the process duration in every core
# params: -
# global: process_duration
# read file: .fileA, .fileB
# count_process_duration
#   add up the total slices the process has occupied in every single core/processor
#   using the data we got in the read_states function
#
function count_process_duration()
{
	while read line
	do 
		tid=$(echo $line | awk '{print $1}')
		psr=$(echo $line | awk '{print $39}')
		lineofB=$(cat .fileB | awk -v tid="$tid" '$1 == tid {print}')
		start_slice=$(echo $line | awk '{t=$14+$15+$16+$17} END {print t}')
		end_slice=$(echo $lineofB | awk '{t=$14+$15+$16+$17} END {print t}')
		interval=$[$end_slice-$start_slice]
		process_duration[$psr]=$[${process_duration[$psr]}+$interval]
	done < .fileA
}

# function: calculate_and_output - calculate the utilization of every core
# params: core_cnt, OUTPUT_FILE 
# globals: process_duration, cpu_total_slice_A, cpu_total_slice_B
# calculate_and_output
#   calculate the utilization of the indexserver process on every single core
#   using the formula introduced in the User Guide
#   output the calculation results finally
#
function calculate_and_output()
{
	core_cnt=$1
	OUTPUT_FILE=$2

	echo "---------------------Time lasted for $time_counter s------------------------------"	
	echo "|    CPU Utilization of Indexserver on every CPU core  "

 
 	line_to_output="$time_counter"		
	for ((i=0; i < $core_cnt; i++ )) 
	do
		cpu_slice=$[(${cpu_total_slice_B[$i]}-${cpu_total_slice_A[$i]})]
		cpu_util=`echo "scale=4;${process_duration[$i]}/$cpu_slice*100"|bc`
		echo "| Core No:$i | CPU Utilization: $cpu_util% | Slices used: ${process_duration[$i]}/$cpu_slice"
		# output the result to output file
		line_to_output+=",$cpu_util"	
	done
	echo " "
	echo $line_to_output >> ${OUTPUT_FILE}	
}

#!/bin/sh
SH=/bin/sh

# Find the <pid> of the Hana Indexserver and check out the number of CPU core
indexserver_pid=$(ps -ef | grep hdb | awk '$8 == "hdbindexserver" {print $2}')
echo "PID of the HanaDB indexserver: $indexserver_pid"

if [ -z $indexserver_pid ];
then
    echo "[Error] Indexserver is not running."
    exit;
fi

core_cnt=$(cat /proc/cpuinfo | awk '/^processor/ {cnt += 1} END {print cnt}')
echo "CPU Core Count: $core_cnt"

# Declaration of the global variables
declare -i time_counter
declare -a cpu_total_slice_A
declare -a cpu_total_slice_B
declare -a process_duration
time_counter=1

# output the header to the output file
OUTPUT_FILE="cpuusage_output.csv"
header="time"
i=0
for ((i=0; i< $core_cnt; i++)) do
	header+=",cpu$i"
done
echo $header >> ${OUTPUT_FILE}

# The while loop keep updating the utilization 
# of the CPU cores with an interval of 1 second
while true
do
	read_states "$core_cnt"
	count_process_duration

	rm .fileA
	rm .fileB

	calculate_and_output "$core_cnt" "${OUTPUT_FILE}"
	
	# Clean up the data
	time_counter+=1
	unset -v process_duration
	unset -v cpu_total_slice_A
	unset -v cpu_total_slice_B
done

echo "Finished."
