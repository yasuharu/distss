
TARGET_PATH="./test/batch"
RUBY="ruby"

if [ $# -eq 1 ]; then
	RUBY=$1
fi
echo $RUBY

for file in `ls $TARGET_PATH`
do
	$RUBY server.rb --start
	$RUBY executer.rb --start

	# 異常終了したら終わる
	$RUBY client.rb -c $TARGET_PATH/$file
	if [ $? -ne 0 ]; then
		$RUBY executer.rb --stop
		$RUBY server.rb --stop
		exit 1
	fi

	$RUBY executer.rb --stop
	$RUBY server.rb --stop
done

