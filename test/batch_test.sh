#! /bin/bash

TARGET_PATH="./test/batch"
RUBY="ruby"


if [ $# -eq 1 ]; then
	RUBY=$1
fi
echo "using $RUBY"

for file in `ls $TARGET_PATH`
do
	echo "----- load $TARGET_PATH/$file -----"
	echo "start server."
	echo "start executer."
	$RUBY server.rb --start
	$RUBY executer.rb --start

	# 異常終了したら終わる
	echo "runngin client."
	$RUBY client.rb -c $TARGET_PATH/$file
	if [ $? -ne 0 ]; then
		echo "failed test."
		$RUBY executer.rb --stop
		$RUBY server.rb --stop
		exit 1
	fi

	echo "success test."
	$RUBY executer.rb --stop
	$RUBY server.rb --stop
done

