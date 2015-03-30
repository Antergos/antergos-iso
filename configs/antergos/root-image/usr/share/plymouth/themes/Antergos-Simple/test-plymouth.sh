#sudo update-alternatives --config default.plymouth
sudo plymouthd #--debug --debug-file=/tmp/plymouth-debug.out
sudo plymouth --show-splash
#sudo plymouth ask-question --prompt=Question
#sudo plymouth ask-for-password --prompt="Password"
#sleep 6
#sudo plymouth pause-progress ; sleep 5 ; sudo plymouth unpause-progress
#sudo plymouth message --text="Message"
for ((I=0; I<5; I++)); do
	sudo plymouth --update=test$I
	sleep 1
done
sudo plymouth quit
