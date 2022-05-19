#!/bin/bash
requiredkernelversion="5.13.0-40"
nodefolder="mvp-pox-node"
configfile="config"
service="etny-vagrant.service"
os=""

ubuntu_20_04(){
#determining if the etny-vagrant service is running. If yes we stop the script as we don't need to run the setup process
echo $os "found. Continuing..."
echo "Finding out if etny-vagrant service is already running"...
systemctl status $service 2>/dev/null | grep "active (running)" > /dev/null
if [ $? -eq 0 ]
then 
	echo "ETNY service already running. Nothing to do. Exiting..."; 
else
	echo "Service not found. Continuing setup..."
	ubuntu_20_04_kernel_check
fi
}

check_wallets(){
#checking if wallets are valid and how much bergs there are in the wallets
local address=$1
addrbergshexa=`curl --silent --data '{"method":"eth_getBalance","params":["'$address'"],"id":0,"jsonrpc":"2.0"}' -H "Content-Type: application/json" -X POST https://blockexplorer.bloxberg.org/api/eth_rpc | awk -F"," '{print $2}' | awk -F":" '{print $2}' | sed 's/"//g' | cut -c 3-`
case $addrbergshexa in
	*"invalid"*) echo "Invalid wallet address. Please fix..." && check_wallet_result=1;;
	*"not found"* | 0) echo "0 bergs. Please get bergs from https://faucet.bloxberg.org/ and run the installer again." && check_wallet_result=1;;
	[a-z0-9]*) 
	var=`bc <<<"scale=10; $(( 16#$addrbergshexa )) / 1000000000000000000"` 
	[[ $var = .* ]] | echo "0"$var "bergs. Continuing..." || echo $var "bergs. Continuing..."&& check_wallet_result=0;;
	*)	echo "Couldn't determine the number of bergs. Internet issue? Exiting..." && check_wallet_result=1;;
esac
}


is_miminum_kernel_version(){
#returning true or false if we have the minimum required kernel version for Ubuntu 20.04
    version=`uname -r` && currentver=${version%-*} 
    if [ "$(printf '%s\n' "$requiredkernelversion" "$currentver" | sort -V | head -n1)" = "$requiredkernelversion" ]; then echo true ; else echo false; fi
 } 

ubuntu_20_04_kernel_check(){
#if we have the right kernel then we run the ansible-playbook and finish installation
echo "Determining if the right kernel is running..."
if [[ ( "$(is_miminum_kernel_version)" = true && $os = "Ubuntu 20.04" ) || ( $(uname -r) = "5.0.0-050000-generic"  && $os = "Ubuntu 18.04") ]]
then  
	echo "The right kernel is running. Continuing setup..."
	echo "Verifying if the repository has been cloned..."
	cd 
	if [ -d $nodefolder ]
	then
		echo "Repository already cloned. Checking if config file exists..."
		cd && cd $nodefolder	
		if [ -f $configfile ]
		then
			echo "Config file found. Checking if wallet address is correctly configured and if it has BERGS... (takes a few seconds)"
			nodeaddrfromfile[0]=`cat ~/$nodefolder/$configfile | grep "^ADDRESS=" | awk -F"=" '{print $2}'`
			nodeaddrfromfile[1]=`cat ~/$nodefolder/$configfile | grep "RESULT_ADDRESS=" | awk -F"=" '{print $2}'`
			for addressfromfile in ${nodeaddrfromfile[@]}; do
				if [[ $addressfromfile == ${nodeaddrfromfile[0]} ]]; then echo -n "Node address   ${addressfromfile}: "; else echo -n "Result address ${addressfromfile}: "; fi
				check_wallets $addressfromfile
				if [[ $check_wallet_result = 1 ]]; then echo "Exiting..." && exit; fi
			done
		else
			echo "Config file not found. How would you like to continue?"
			ubuntu_20_04_config_file_choice
		fi
		echo "Running ansible-playbook script..."	
		sudo ansible-galaxy install uoi-io.libvirt && sudo ansible-playbook -i localhost, playbook.yml -e "ansible_python_interpreter=/usr/bin/python3"	
		if [ $? -eq 0 ]; then echo "Node installation completed successfully. Please allow up to 24h to see transactions on the blockchain. " && exit; fi
	else
		ubuntu_20_04_clone_repository
	fi
else 
	ubuntu_20_04_update_ansible
fi
}

ubuntu_20_04_config_file_choice(){
#if the config file doesn't exist we offer the either generate one with random wallets or we get the wallets from input
echo "1) Generate config file with random wallets." 
echo "2) Type wallets. "
echo "3) Exit. Rerun the script when config file exists..."
echo -n "[Type your choice to continue]:" && read choice
case "$choice" in 
	1) 
		echo "Generating config file..."
		cd && $nodefolder/utils/linux/ethkey generate random | awk '!/public:/' | awk '{gsub("secret:","PRIVATE_KEY="); print}' | awk '{gsub("address:","ADDRESS="); print}' | awk '{ gsub(/ /,""); print }' | sed -n 'h;n;p;g;p' >> ~/$nodefolder/$configfile
		cd && $nodefolder/utils/linux/ethkey generate random | awk '!/public:/' | awk '{gsub("secret:","RESULT_PRIVATE_KEY="); print}' | awk '{gsub("address:","RESULT_ADDRESS="); print}' | awk '{ gsub(/ /,""); print }' | sed -n 'h;n;p;g;p' >> ~/$nodefolder/$configfile
		if [ -f $nodefolder/$configfile ]
		then 
			echo "Config file generated successfully. Continuing..." 
			echo -e '\033[1mMAKE SURE YOU REQUEST BERGS FROM https://faucet.bloxberg.org/ FOR THE WALLETS BELOW BEFORE CONTINUING\033[0m'
			cat ~/$nodefolder/$configfile | grep "^ADDRESS=" | awk -F"=" '{print $2}'
			cat ~/$nodefolder/$configfile | grep "RESULT_ADDRESS=" | awk -F"=" '{print $2}'
			echo -e '\033[1mWallet addresses can also be seen in the config file.\033[0m'
			read -rsn1 -p"Press any key to continue...";echo
			ubuntu_20_04_kernel_check
		else echo "Something went wrong. Seek Help!" && exit
		fi
	;;
	2) 
		echo "Type/Paste wallet details below..."
		nodeaddr=("Node Address: " "Node Private Key: " "Result Address: " "Result Private Key: ")
		IFS=""
		for address in ${nodeaddr[@]}; do
			case $address in
				${nodeaddr[0]})
				while true
				do
					echo -n $address && read nodeaddress
					if [[ $nodeaddress = "" ]]; then echo "Node address cannot be empty."; else check_wallets $nodeaddress; fi
					if [[ $check_wallet_result = 0 ]]; then break; fi
				done;;
				${nodeaddr[2]})
					while true
					do
						echo -n $address && read resultaddress
						if [[ $nodeaddress = $resultaddress ]]
						then 
							echo "Result address must be different than the node address. Try a different address..."
						else
							check_wallets $resultaddress
							if [[ $check_wallet_result = 0 ]]; then break; fi
						fi
					done;;
				${nodeaddr[1]})
					while true
					do
						echo -n $address && read nodeprivatekey
						if [[ ${#nodeprivatekey} = 64 && $nodeprivatekey =~ ^[a-zA-Z0-9]*$ ]]
						then
							break
						else echo "Invalid result private key. Please try again..."
						fi
					done;;
				${nodeaddr[3]})
					while true
					do
						echo -n $address && read resultprivatekey
						if [[ ${#resultprivatekey} = 64 && $resultprivatekey =~ ^[a-zA-Z0-9]*$ ]]
						then
							if [[ $nodeprivatekey = $resultprivatekey ]]
							then
								echo "Result private key must be different than the node private key. Try a different private key..."
							else
								break
							fi
						else echo "Invalid result private key. Please try again..."
						fi
					done;;

			esac
		done
		echo "ADDRESS="$nodeaddress >> ~/$nodefolder/$configfile
		echo "PRIVATE_KEY="$nodeprivatekey >> ~/$nodefolder/$configfile
		echo "RESULT_ADDRESS="$resultaddress >> ~/$nodefolder/$configfile
		echo "RESULT_PRIVATE_KEY="$resultprivatekey >> ~/$nodefolder/$configfile
		if [ -f ~/$nodefolder/$configfile ]; then echo "Config file generated successfully. Continuing..." && ubuntu_20_04_kernel_check; else echo "Something went wrong. Seek Help!" && exit; fi
	;;
	3) echo "Exiting..." && exit;;
	*) echo "Invalid choice. Please choose an option below..." && ubuntu_20_04_config_file_choice;;
esac
}

ubuntu_20_04_clone_repository(){
#establishing if the repository has been cloned and if not we clone it
echo "Verifying if the repository has been cloned..."
cd 
if [ -d $nodefolder ]
then
	echo "Repository already cloned. Continuing..."
	ubuntu_20_04_ansible_playbook
else 
	cd && git clone https://github.com/ethernity-cloud/mvp-pox-node.git
	if [ $? -eq 0 ]; then ubuntu_20_04_clone_repository; else echo "Error occurred. Please run the script again."; fi
fi
}

ubuntu_20_04_ansible_playbook(){
#running the ansible-playbook command and restart system automatically
echo "Running ansible-playbook..."
cd && cd $nodefolder
sudo ansible-galaxy install uoi-io.libvirt
sudo ansible-playbook -i localhost, playbook.yml -e "ansible_python_interpreter=/usr/bin/python3"
if [ $? -eq 0 ]
then 
	echo "Restarting system. Please run the installer script afterwards to continue the setup."
	sec=30
	while [ $sec -ge 0 ]; do echo -n "Restarting system in [CTRL+C to cancel]: " && echo -ne "$sec\033[0K\r" && let "sec=sec-1" && sleep 1; done
	sudo reboot
fi
}


ubuntu_20_04_update_ansible(){
#If we don't have the right kernel running that means we didn't update the system
echo "We don't have the right kernel running."
echo "Updating system, kernel and installing ansible..."
sudo sudo apt-add-repository --yes --update ppa:ansible/ansible && sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y &&  sudo apt -y install software-properties-common ansible
if [ $? -eq 0 ]
then 
	echo "Update successfull. Continuing..."
	ubuntu_20_04_clone_repository	
fi
}

ubuntu(){
#Getting which version of Ubuntu is instaled
echo "Ubuntu OS found. Determining version..."
case $(awk '/^VERSION_ID=/' /etc/*-release 2>/dev/null | awk -F'=' '{ print tolower($2) }' | tr -d '"') in
	20.04) 
		os='Ubuntu 20.04'
		ubuntu_20_04;;
	18.04) 
		os='Ubuntu 18.04'
		ubuntu_20_04;;
	22.04) echo "Ubuntu 22.04 is not yet supported. Exiting...";;
	*) echo "Version not supported. Exiting..."
esac
}

start(){
#getting which Linux distribution is installed
echo "Getting distro..."
case $(awk '/^ID=/' /etc/*-release 2>/dev/null | awk -F'=' '{ print tolower($2) }' | tr -d '"') in
	ubuntu) ubuntu;;
#	debian) echo "debian distro Found. Not Supported. Exiting...";;
#	centos) echo "centos distro Found. Not Supported. Exiting...";;
#	manjaro) echo "manjaro distro Found. Not Supported. Exiting...";;
#	arch) echo "arch distro Found. Not Supported. Exiting...";;
#	rhel) echo "red hat  distro Found. Not Supported. Exiting...";;
#	fedora) echo "fedora distro Found. Not Supported. Exiting...";;
	*) echo "Could not determine Distro. Exiting..."
esac
}
start
