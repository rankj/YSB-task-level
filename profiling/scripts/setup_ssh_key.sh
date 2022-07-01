FILEPATH=""
PW=""
USERNAME=""
KEY=""


if [ "$1" == "" ]; then
HELP="true"
fi
if [ "${HELP}" == "true" ]
then
cat <<EOF
###############################################
### Automatic SSH Key Authentication Script ###
###############################################

Description: This script automatically connects to several servers using ssh and deposits 
your personal public key in the authorized_keys file on the server so that you can connect 
via ssh with key authentication from now on.

This script requires sshpass to be installed on this system (not on the remote hosts)

Only use this script if the servers you want to deposit your ssh key on have password 
authentication on

Usage: Call the script and enter the required information:

Parameters:
	-u  or  -username		Username used to login on server
	-f  or  -file			Directory of .txt file in which all hostnames of the
					servers you want to connect to are written
	-p  or  -password		Password used to login on server
	-k  or  -key 			directory of your public key file
	-h  or  -help  or  no option	Prints this help menu
	
EOF
exit
fi
SSHPASS_FLAG=`which sshpass`
if [ "$SSHPASS_FLAG" == "" ]; then
  echo "###################################"
  echo "#             SSHPASS             #"
  echo "###################################"
  echo "This script requires sshpass to be installed on this system (not on the remote hosts)"
  echo "Please install sshpass:"
  echo "  -Debian/Ubuntu: apt-get install sshpass"
  echo "  -SUSE/SLES: zypper install sshpass"
  echo "  -CentOS/RHEL: yum install sshpass"
  echo "  -Fedora: dnf install sshpass "
  echo ""
  echo "Exiting"
  exit
fi

while [ "$1" != "" ]; do
	case $1 in
		-f| -file )		shift 
					FILEPATH=$1
					;;
		-u| -username )		shift 
					USERNAME=$1
					;;
		-p| -password )		shift 
					PW=$1
					;;
		-k| -key )		shift 
					KEY=$1
					;;
		-h| -help )		shift
					HELP=true
					;;	
	esac
	shift
done
if [ "$USERNAME" == "" ] || [ "$PW" == "" ]; then
  echo "###################################"
  echo "#      Username and Password      #"
  echo "###################################"
  echo "You need to specify username AND password for the initial connection between this system and the remote host"
  echo "Please specify -u <Username> AND -p <Password>"
  echo "Exiting"
  exit
fi
if [ "$KEY" == "" ]; then
echo "###################################"
echo "#             SSH Key             #"
echo "###################################"
echo "You didn't specify a public ssh key"
echo "Please generate a passwordless SSH Key using 'ssh-keygen'"
echo "The private key needs to be deposited in $HOME/.ssh/id_rsa with permission 600"
echo "Call this script using option -k to specify the path to your public key file"
echo ""
echo "[DEFAULT] You may also choose to continue with the default settings which assume the public key to be deposited in YSB/conf/id_rsa.pub"
  read -p "[DEFAULT] Would you like to continue using YSB/conf/id_rsa.pub (Y/N)? " CONT
  CONT=$(echo "${CONT}" | tr '[:lower:]' '[:upper:]')
  if [ "$CONT" != "Y" ]; then
    echo "Exiting";
    exit  
  fi
fi

if [ "$FILEPATH" == "" ]; then
echo "###################################"
echo "#            Hosts File           #"
echo "###################################"
  echo "No Filepath for cluster.txt provided"
  read -p "[DEFAULT] Would you like to continue using YSB/conf/cluster.txt(Y/N)? " CONT
  CONT=$(echo "${CONT}" | tr '[:lower:]' '[:upper:]')
  if [ "$CONT" != "Y" ]; then
    echo "Exiting";
    exit  
  fi
  FILEPATH="../../conf/cluster.txt"
fi
HOSTS=`cat $FILEPATH | awk '{print $1}'`

echo "$HOSTS" | while IFS= read -r line
do
	concat="$USERNAME"@"$line"
	sshpass -p $PW ssh-copy-id -f -o StrictHostKeyChecking=no -i $KEY $concat
	case $? in
		0) 	
			echo Key\ successfully\ added\ to\ $line 
			;;
		1)
                        ;;
		2)
                        ;;
		3)
                        echo General\ runtime\ error\ for\ $line
                        ;;
		4)
                        ;;
		5)
                        echo Invalid\ password\ for\ $line
                        ;;
		6)
                        ;;
  esac
done


echo "Note: The first time you log in via pubkey authentication the system prompts you that you confirm the authenticity of the system"
echo "To make sure that scripts can automatically establish a connection you should perform the first login manually!"
echo "$HOSTS" | while IFS= read -r line
do
  echo "ssh ${USERNAME}@${HOSTS}"
done
echo ""
echo "[FINISHED] Remember to clear your history from your credentials!!!"


 
