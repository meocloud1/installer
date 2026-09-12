#!/bin/sh

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    yum install -y wget curl
elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    apt-get install -y wget curl	
fi

function CopyRight() {
  clear
  echo "########################################################"
  echo "#                                                      #"
  echo "#  Windows Install Script                              #"
  echo "#                                                      #"
  echo "#  Author: meocloud                                    #"
  echo "#  Blog: https://meocloud.my.id                        #"
  echo "#  Feedback: https://meocloud.my.id                    #"
  echo "#  Last Modified: 11-01-2023                           #"
  echo "#                                                      #"
  echo "#  Supported by meocloud                               #"
  echo "#                                                      #"
  echo "########################################################"
  echo -e "\n"
}

function isValidIp() {
  local ip="$1"
  local ret=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=(${ip//\./ })
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    ret=$?
  fi
  return $ret
}

function ipCheck() {
  isLegal=0
  for add in $MAINIP $GATEWAYIP $NETMASK; do
    isValidIp "$add"
    if [ $? -eq 1 ]; then
      isLegal=1
    fi
  done
  return $isLegal
}

function GetIp() {
  MAINIP=$(ip route get 1 | awk -F 'src ' '{print $2}' | awk '{print $1}')
  GATEWAYIP=$(ip route | grep default | awk '{print $3}' | head -1)
  SUBNET=$(ip -o -f inet addr show | awk '/scope global/{sub(/[^.]+\//,"0/",$4);print $4}' | head -1 | awk -F '/' '{print $2}')
  value=$(( 0xffffffff ^ ((1 << (32 - $SUBNET)) - 1) ))
  NETMASK="$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}

function UpdateIp() {
  read -r -p "Your IP: " MAINIP
  read -r -p "Your Gateway: " GATEWAYIP
  read -r -p "Your Netmask: " NETMASK
}

function SetNetwork() {
  isAuto='0'
  if [[ -f '/etc/network/interfaces' ]];then
    [[ ! -z "$(sed -n '/iface.*inet static/p' /etc/network/interfaces)" ]] && isAuto='1'
    [[ -d /etc/network/interfaces.d ]] && {
      cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
      [[ "$cfgNum" -ne '0' ]] && {
        for netConfig in $(ls -1 /etc/network/interfaces.d/*.cfg)
        do
          [[ ! -z "$(cat "$netConfig" | sed -n '/iface.*inet static/p')" ]] && isAuto='1'
        done
      }
    }
  fi

  if [[ -d '/etc/sysconfig/network-scripts' ]];then
    cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
    [[ "$cfgNum" -ne '0' ]] && {
      for netConfig in $(ls -1 /etc/sysconfig/network-scripts/ifcfg-* | grep -v 'lo$' | grep -v ':[0-9]\{1,\}')
      do
        [[ ! -z "$(cat "$netConfig" | sed -n '/BOOTPROTO.*[sS][tT][aA][tT][iI][cC]/p')" ]] && isAuto='1'
      done
    }
  fi
}

function NetMode() {
  CopyRight

  if [ "$isAuto" == '0' ]; then
    read -r -p "Use DHCP to configure network automatically? [Y/n]:" input
    case $input in
      [yY][eE][sS]|[yY]) NETSTR='' ;;
      [nN][oO]|[nN]) isAuto='1' ;;
      *) NETSTR='' ;;
    esac
  fi

  if [ "$isAuto" == '1' ]; then
    GetIp
    ipCheck
    if [ $? -ne 0 ]; then
      echo -e "Error occurred when detecting ip. Please input manually.\n"
      UpdateIp
    else
      CopyRight
      echo "IP: $MAINIP"
      echo "Gateway: $GATEWAYIP"
      echo "Netmask: $NETMASK"
      echo -e "\n"
      read -r -p "Confirm? [Y/n]:" input
      case $input in
        [yY][eE][sS]|[yY]) ;;
        [nN][oO]|[nN])
          echo -e "\n"
          UpdateIp
          ipCheck
          [[ $? -ne 0 ]] && {
            clear
            echo -e "Input error!\n"
            exit 1
          }
        ;;
        *) ;;
      esac
    fi
    NETSTR="--ip-addr ${MAINIP} --ip-gate ${GATEWAYIP} --ip-mask ${NETMASK}"
  fi
}

function RHELImageBootConf() {
  touch /tmp/bootconf.sh
  echo '#!/bin/sh'>/tmp/bootconf.sh

  staticIp='1'
  if [ "$isAuto" == '1' ]; then
    echo -e "\n"
    read -r -p "Writing static ip to system? [Y/n]: " input
    case $input in
      [yY][eE][sS]|[yY]) staticIp='0' ;;
      *) staticIp='1' ;;
    esac
  fi

  if [ "$isAuto" == '1' ] && [ "$staticIp" == '0' ]; then
    cat >>/tmp/bootconf.sh <<EOF
sed -i 's/dhcp/static/' /etc/sysconfig/network-scripts/ifcfg-eth0;
echo -e "IPADDR=$MAINIP\nNETMASK=$NETMASK\nGATEWAY=$GATEWAYIP\nDNS1=8.8.8.8\nDNS2=8.8.4.4" >> /etc/sysconfig/network-scripts/ifcfg-eth0
EOF
  fi
  cat >>/tmp/bootconf.sh <<EOF
rm -f /etc/rc.d/rc.local
cp -f /etc/rc.d/rc.local.bak /etc/rc.d/rc.local
rm -rf /bootconf.sh
shutdown -r now
EOF
  sed -i '/sbin\/reboot/i\ sync; umount \\$(list-devices partition |head -n1); mount -t ext4 \\$(list-devices partition |head -n1) \/mnt; cp -f \/mnt\/etc\/rc.d\/rc.local \/mnt\/etc\/rc.d\/rc.local.bak; chmod +x \/mnt\/etc\/rc.d\/rc.local; cp -f \/bootconf.sh \/mnt\/bootconf.sh; chmod 755 \/mnt\/bootconf.sh; echo \"\/bootconf.sh\" >> \/mnt\/etc\/rc.d\/rc.local; sync; umount \/mnt; \\' /tmp/MeoNET.sh
  sed -i '/newc/i\cp -f \/tmp\/bootconf.sh \/tmp\/boot\/bootconf.sh'  /tmp/MeoNET.sh
}

function Start() {
  CopyRight

  isCN='0'
  geo=$(curl -fsSL -m 10 http://ipinfo.io/json | grep "\"country\": \"CN\"")
  if [[ "$geo" != "" ]];then
    isCN='1'
  fi

  if [ "$isAuto" == '0' ]; then
    echo "Network Type: DHCP"
  else
    echo "IP: $MAINIP"
    echo "Gateway: $GATEWAYIP"
    echo "Netmask: $NETMASK"
  fi

  [[ "$isCN" == '1' ]] && echo "Location: Domestic"

  if [ -f "/tmp/MeoNET.sh" ]; then
    rm -f /tmp/MeoNET.sh
  fi
  curl -sSL -o /tmp/MeoNET.sh 'https://raw.githubusercontent.com/meocloud1/installer/refs/heads/master/MeoNet.sh' && chmod a+x /tmp/MeoNET.sh
  #curl -sSL -o /tmp/MeoNET.sh 'https://raw.githubusercontent.com/meocloud1/installer/refs/heads/master/MeoNet.sh' && chmod a+x /tmp/MeoNET.sh

  CMIRROR=''
  CVMIRROR=''
  DMIRROR=''
  UMIRROR=''
  if [[ "$isCN" == '1' ]];then
    CMIRROR="--mirror http://mirrors.cloud.tencent.com/centos"
    CVMIRROR="--mirror http://mirrors.cloud.tencent.com/centos-vault"
    DMIRROR="--mirror http://mirrors.cloud.tencent.com/debian"
    UMIRROR="--mirror http://mirrors.cloud.tencent.com/ubuntu"
  fi

  sed -i 's/$1$4BJZaD0A$y1QykUnJ6mXprENfwpseH0/$1$7R4IuxQb$J8gcq7u9K0fNSsDNFEfr90/' /tmp/MeoNET.sh

  echo -e "\nPlease select an OS:"
  echo "  1) Windows Server Datacenter 2012R2"
  echo "  2) Windows Server Datacenter 2016"
  echo "  3) Windows Server Datacenter 2019"
  echo "  4) Windows Server Datacenter 2022"
  echo "  5) Windows 10"
  echo "  6) Windows 11"
  echo "  7) Windows 7"
  echo "  8) Custom Windows Link"
  echo "  9) Exit"
  echo -ne "\nYour option: "
  read N
  case $N in
    1) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows2012R2.gz' "$DMIRROR" ;;
    2) echo -e "\nPassword: Pwd@CentOS\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows2016.gz' "$DMIRROR" ;;
    3) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows2019.gz' "$DMIRROR" ;;
    4) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows2022.gz' "$DMIRROR" ;;
    5) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows10.gz' "$DMIRROR" ;;
    6) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows11.gz' "$DMIRROR" ;;
    7) echo -e "\nPassword: Pwd@Linux\n"; RHELImageBootConf; read -s -n1 -p "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://files.meocloud.my.id/0:/Windows/windows71.gz' "$DMIRROR" ;;
    8)
      echo -e "\n"
      read -r -p "Custom image URL: " imgURL
      echo -e "\n"
      read -r -p "Are you sure start reinstall? [y/N]: " input
      case $input in
        [yY][eE][sS]|[yY]) bash /tmp/MeoNET.sh "$NETSTR" -dd "$imgURL" "$DMIRROR" ;;
        *) clear; echo "Canceled by user!"; exit 1;;
      esac
      ;;
    9) exit 0;;
    *) echo "Wrong input!"; exit 1;;
  esac
}

SetNetwork
NetMode
Start#!/bin/sh

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    yum install -y wget curl
elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    apt-get install -y wget curl	
fi

function CopyRight() {
  clear
  echo "########################################################"
  echo "#                                                      #"
  echo "#  Windows Install Script                              #"
  echo "#                                                      #"
  echo "#  Author: meocloud                                    #"
  echo "#  Blog: https://meocloud.my.id                        #"
  echo "#  Feedback: https://meocloud.my.id                    #"
  echo "#  Last Modified: 11-01-2026                           #"
  echo "#                                                      #"
  echo "#  Supported by meocloud                               #"
  echo "#                                                      #"
  echo "########################################################"
  echo -e "\n"
}

function isValidIp() {
  local ip="$1"
  local ret=1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    ip=(${ip//\./ })
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    ret=$?
  fi
  return $ret
}

function ipCheck() {
  isLegal=0
  for add in $MAINIP $GATEWAYIP $NETMASK; do
    isValidIp "$add"
    if [ $? -eq 1 ]; then
      isLegal=1
    fi
  done
  return $isLegal
}

function GetIp() {
  MAINIP=$(ip route get 1 | awk -F 'src ' '{print $2}' | awk '{print $1}')
  GATEWAYIP=$(ip route | grep default | awk '{print $3}' | head -1)
  SUBNET=$(ip -o -f inet addr show | awk '/scope global/{sub(/[^.]+\//,"0/",$4);print $4}' | head -1 | awk -F '/' '{print $2}')
  value=$(( 0xffffffff ^ ((1 << (32 - $SUBNET)) - 1) ))
  NETMASK="$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}

function UpdateIp() {
  read -r -p "Your IP: " MAINIP
  read -r -p "Your Gateway: " GATEWAYIP
  read -r -p "Your Netmask: " NETMASK
}

function SetNetwork() {
  isAuto='0'
  if [[ -f '/etc/network/interfaces' ]];then
    [[ ! -z "$(sed -n '/iface.*inet static/p' /etc/network/interfaces)" ]] && isAuto='1'
    [[ -d /etc/network/interfaces.d ]] && {
      cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
      [[ "$cfgNum" -ne '0' ]] && {
        for netConfig in $(ls -1 /etc/network/interfaces.d/*.cfg)
        do
          [[ ! -z "$(cat "$netConfig" | sed -n '/iface.*inet static/p')" ]] && isAuto='1'
        done
      }
    }
  fi

  if [[ -d '/etc/sysconfig/network-scripts' ]];then
    cfgNum="$(find /etc/network/interfaces.d -name '*.cfg' |wc -l)" || cfgNum='0'
    [[ "$cfgNum" -ne '0' ]] && {
      for netConfig in $(ls -1 /etc/sysconfig/network-scripts/ifcfg-* | grep -v 'lo$' | grep -v ':[0-9]\{1,\}')
      do
        [[ ! -z "$(cat "$netConfig" | sed -n '/BOOTPROTO.*[sS][tT][aA][tT][iI][cC]/p')" ]] && isAuto='1'
      done
    }
  fi
}

function NetMode() {
  CopyRight

  if [ "$isAuto" == '0' ]; then
    read -r -p "Use DHCP to configure network automatically? [Y/n]:" input
    case $input in
      [yY][eE][sS]|[yY]) NETSTR='' ;;
      [nN][oO]|[nN]) isAuto='1' ;;
      *) NETSTR='' ;;
    esac
  fi

  if [ "$isAuto" == '1' ]; then
    GetIp
    ipCheck
    if [ $? -ne 0 ]; then
      echo -e "Error occurred when detecting ip. Please input manually.\n"
      UpdateIp
    else
      CopyRight
      echo "IP: $MAINIP"
      echo "Gateway: $GATEWAYIP"
      echo "Netmask: $NETMASK"
      echo -e "\n"
      read -r -p "Confirm? [Y/n]:" input
      case $input in
        [yY][eE][sS]|[yY]) ;;
        [nN][oO]|[nN])
          echo -e "\n"
          UpdateIp
          ipCheck
          [[ $? -ne 0 ]] && {
            clear
            echo -e "Input error!\n"
            exit 1
          }
        ;;
        *) ;;
      esac
    fi
    NETSTR="--ip-addr ${MAINIP} --ip-gate ${GATEWAYIP} --ip-mask ${NETMASK}"
  fi
}

function RHELImageBootConf() {
  touch /tmp/bootconf.sh
  echo '#!/bin/sh'>/tmp/bootconf.sh

  staticIp='1'
  if [ "$isAuto" == '1' ]; then
    echo -e "\n"
    read -r -p "Writing static ip to system? [Y/n]: " input
    case $input in
      [yY][eE][sS]|[yY]) staticIp='0' ;;
      *) staticIp='1' ;;
    esac
  fi

  if [ "$isAuto" == '1' ] && [ "$staticIp" == '0' ]; then
    cat >>/tmp/bootconf.sh <<EOF
sed -i 's/dhcp/static/' /etc/sysconfig/network-scripts/ifcfg-eth0;
echo -e "IPADDR=$MAINIP\nNETMASK=$NETMASK\nGATEWAY=$GATEWAYIP\nDNS1=8.8.8.8\nDNS2=8.8.4.4" >> /etc/sysconfig/network-scripts/ifcfg-eth0
EOF
  fi
  cat >>/tmp/bootconf.sh <<EOF
rm -f /etc/rc.d/rc.local
cp -f /etc/rc.d/rc.local.bak /etc/rc.d/rc.local
rm -rf /bootconf.sh
shutdown -r now
EOF
  sed -i '/sbin\/reboot/i\ sync; umount \\$(list-devices partition |head -n1); mount -t ext4 \\$(list-devices partition |head -n1) \/mnt; cp -f \/mnt\/etc\/rc.d\/rc.local \/mnt\/etc\/rc.d\/rc.local.bak; chmod +x \/mnt\/etc\/rc.d\/rc.local; cp -f \/bootconf.sh \/mnt\/bootconf.sh; chmod 755 \/mnt\/bootconf.sh; echo \"\/bootconf.sh\" >> \/mnt\/etc\/rc.d\/rc.local; sync; umount \/mnt; \\' /tmp/MeoNET.sh
  sed -i '/newc/i\cp -f \/tmp\/bootconf.sh \/tmp\/boot\/bootconf.sh'  /tmp/MeoNET.sh
}

function Start() {
  CopyRight

  isCN='0'
  geo=$(curl -fsSL -m 10 http://ipinfo.io/json | grep "\"country\": \"CN\"")
  if [[ "$geo" != "" ]];then
    isCN='1'
  fi

  if [ "$isAuto" == '0' ]; then
    echo "Network Type: DHCP"
  else
    echo "IP: $MAINIP"
    echo "Gateway: $GATEWAYIP"
    echo "Netmask: $NETMASK"
  fi

  [[ "$isCN" == '1' ]] && echo "Location: Domestic"

  if [ -f "/tmp/MeoNET.sh" ]; then
    rm -f /tmp/MeoNET.sh
  fi
  curl -sSL -o /tmp/MeoNET.sh 'https://raw.githubusercontent.com/meocloud1/installer/refs/heads/master/MeoNet.sh' && chmod a+x /tmp/MeoNET.sh
  #curl -sSL -o /tmp/MeoNET.sh 'https://raw.githubusercontent.com/meocloud1/installer/refs/heads/master/MeoNet.sh' && chmod a+x /tmp/MeoNET.sh

  CMIRROR=''
  CVMIRROR=''
  DMIRROR=''
  UMIRROR=''
  if [[ "$isCN" == '1' ]];then
    CMIRROR="--mirror http://mirrors.cloud.tencent.com/centos"
    CVMIRROR="--mirror http://mirrors.cloud.tencent.com/centos-vault"
    DMIRROR="--mirror http://mirrors.cloud.tencent.com/debian"
    UMIRROR="--mirror http://mirrors.cloud.tencent.com/ubuntu"
  fi

  sed -i 's/$1$4BJZaD0A$y1QykUnJ6mXprENfwpseH0/$1$7R4IuxQb$J8gcq7u9K0fNSsDNFEfr90/' /tmp/MeoNET.sh

  echo -e "\nPlease select an OS:"
  echo "  1) Windows Server Datacenter 2012R2"
  echo "  2) Windows Server Datacenter 2016"
  echo "  3) Windows Server Datacenter 2019"
  echo "  4) Windows Server Datacenter 2022"
  echo "  5) Windows 10"
  echo "  6) Windows 11"
  echo "  7) Windows 7"
  echo "  8) Custom Windows Link"
  echo "  9) Exit"
  echo -ne "\nYour option: "
  read N
  case $N in
    1) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows2012R2_UEFI.gz' "$DMIRROR" ;;
    2) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows2016_UEFI.gz' "$DMIRROR" ;;
    3) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows2019_UEFI.gz' "$DMIRROR" ;;
    4) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows2022_UEFI.gz' "$DMIRROR" ;;
    5) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows10_UEFI.gz' "$DMIRROR" ;;
    6) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://list.ohmigoo.eu.org/13:/UEFI/Windows11_UEFI.gz' "$DMIRROR" ;;
    7) echo -e "Press any key to continue..." ; bash /tmp/MeoNET.sh "$NETSTR" -dd 'https://times.meocloud.my.id/10:/windows2025_uefi.gz' "$DMIRROR" ;;
    8)
      echo -e "\n"
      read -r -p "Custom image URL: " imgURL
      echo -e "\n"
      read -r -p "Are you sure start reinstall? [y/N]: " input
      case $input in
        [yY][eE][sS]|[yY]) bash /tmp/MeoNET.sh "$NETSTR" -dd "$imgURL" "$DMIRROR" ;;
        *) clear; echo "Canceled by user!"; exit 1;;
      esac
      ;;
    9) exit 0;;
    *) echo "Wrong input!"; exit 1;;
  esac
}

SetNetwork
NetMode
Start
