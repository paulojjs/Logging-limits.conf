#!bin/bash
#This program sends mail when some new violations happen. Put this script to the crontab of the root user. We collect the report to "message" file and  this file is sent as the body of the mail. Mutt must be configure for the root user.

function send_mail
{
	cat $DIR/message | mail -s "[VIOLATION] Limits hit Detected" devs@codelearn.org pauldaviesc@gmail.com -aFrom:pocha@codelearn.org 
}
#This function is used to do some opearion during the exit
function finish
{
	/bin/cp $DIR/currop $DIR/prevop
	/bin/cp $DIR/currfsizelog $DIR/prevfsizelog
	/bin/cp $DIR/currnoproclog $DIR/prevnoproclog
	/bin/cp $DIR/currnofilelog $DIR/prevnofilelog
	/bin/cp $DIR/currmemlocklog $DIR/prevmemlocklog
	/bin/cp $DIR/currcputimelog $DIR/prevcputimelog
	/bin/cp $DIR/currstacklog $DIR/prevstacklog
	/bin/cp $DIR/curraslog $DIR/prevaslog
	/bin/cp $DIR/currrlimitlog $DIR/prevrlimitlog

	#$sendmail is passed in as an arg. send mail only if it is set to >0.
	if [[ $1 -gt 0 ]]
	then
		send_mail
	fi
}

function main
{
	#Set the directory where you want to 
	DIR=`dirname $0`
	/bin/echo > $DIR/message
	sendmail=0
	num_logs=`grep num_log /etc/audit/auditd.conf | cut -d'=' -f2`
	#Checking for  STACK violations. We check whether any new process has been killed by SIGSEGV in audit log.
	/bin/grep sig=11 /var/log/audit/audit.log > $DIR/currstacklog
	/usr/bin/diff -N --suppress-common-lines $DIR/currstacklog $DIR/prevstacklog | grep '^< type=ANOM_ABEND' > $DIR/diffop 

	if [[ $? -eq 0 ]] #If new violation has happened from last checkpoint then add it to message.
	then
		echo "STACK VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 0 $num_logs | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#Checking for  CPU time violations. We check whether any new process has been killed by SIGXCPU in audit log.
	/bin/grep sig=24 /var/log/audit/audit.log > $DIR/currcputimelog
	/usr/bin/diff -N --suppress-common-lines $DIR/currcputimelog $DIR/prevcputimelog | grep '^< type=ANOM_ABEND' > $DIR/diffop 

	if [[ $? -eq 0 ]] #If new violation has happened from last checkpoint then add it to message.
	then
		echo "SOFT CPU TIME VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 0  $num_logs | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	/sbin/aureport -x --failed --summary  -i -if /var/log/audit/audit.log > $DIR/currop
	#Check  for the system calls that has failed.Take the diffs of the current and previous output to see whether a new violation has happened from last check point.
	/usr/bin/diff -N --suppress-common-lines $DIR/currop $DIR/prevop | grep '^<' > $DIR/diffop 
	if [[ $? -gt 0 ]] #If no new violation has happened from last checkpoint then exit.
	then
		finish $sendmail
		exit
	fi

	#If there is fsize violation add it to message.
	/sbin/ausearch  -k fsize -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/currfsizelog
	/usr/bin/diff -N --suppress-common-lines $DIR/currfsizelog $DIR/prevfsizelog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "FILE SIZE VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 1 $num_logs  | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#If there is a noproc violation add it to message.
	/sbin/ausearch -e -EAGAIN -k noproc -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/currnoproclog
	/usr/bin/diff -N --suppress-common-lines $DIR/currnoproclog $DIR/prevnoproclog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "PROCESS NUMBER VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 1  $num_logs | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#If there is a nofile violation add it to message.
	/sbin/ausearch  -k nofile -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/currnofilelog
	/usr/bin/diff -N --suppress-common-lines $DIR/currnofilelog $DIR/prevnofilelog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "NUMBER OF FILES VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 1 $num_logs   | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#If there is a memlock violation add it to message.
	/sbin/ausearch  -k memlock -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/currmemlocklog
	/usr/bin/diff -N --suppress-common-lines $DIR/currmemlocklog $DIR/prevmemlocklog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "MEMLOCK VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 1  $num_logs | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#If there is as violation add it to message.
	/sbin/ausearch  -k as -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/curraslog
	/usr/bin/diff -N --suppress-common-lines $DIR/curraslog $DIR/prevaslog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "AS VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 1  $num_logs | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#If there is a failed setrlimit violation add it to message.
	/sbin/ausearch  -k rlimit -sv no -if /var/log/audit/audit.log 2>/dev/null > $DIR/currrlimitlog
	/usr/bin/diff -N --suppress-common-lines $DIR/currrlimitlog $DIR/prevrlimitlog | grep '^< type=SYSCALL' > $DIR/diffop

	if [[ $? -eq 0 ]] 
	then
		echo "RLIMIT VIOLATION" >> $DIR/message
		python $DIR/preprocess.py $DIR/diffop $DIR/op 2 $num_logs  | /usr/bin/sort | /usr/bin/uniq -c  >> $DIR/message
		sendmail=1
	fi

	#Now the report is in message file.We will be sending the mail with message as body.
	finish $sendmail
}

main
