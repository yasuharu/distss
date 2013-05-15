
TARGET_PATH="./test/batch"
for file in `ls $TARGET_PATH`
do
	ruby server.rb --start
	ruby executer.rb --start

	# 異常終了したら終わる
	ruby client.rb -c $TARGET_PATH/$file
	if [ $? -ne 0 ]; then
		ruby executer.rb --stop
		ruby server.rb --stop
		exit 1
	fi

	ruby executer.rb --stop
	ruby server.rb --stop
done

