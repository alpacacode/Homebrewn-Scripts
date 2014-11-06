#!/bin/bash
##########
# Script for automatic checking of HP ILO login credentials.
# Running this script requires an argument pointing to a file containing the iLO hostnames or IPs to connect to.
# I checked this script with all known iLO versions 1, 2, 3 and 4, and it worked with all of them (the login procedure for versions 1/2 and 3/4 are identical).
#
# Whether you want to check local iLO or LDAP/AD accounts actually doesn’t matter, it will work with both. 
# But be aware that LDAP authentication on iLO 1 and 2 requires you to specify the full Distinguished Name of your account on the iLO login page or in this script, e.g. something like “CN=adminuser,OU=departmen1,OU=top,DC=domain,DC=local”.
# You need to enter that if you want to connect to iLO1/2 with Firefox for example too, but not with IE as an Active-X plugin there actually takes care of transforming your short user name to the DN.
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
# Reference: http://alpacapowered.wordpress.com/2013/01/14/ilo-login-check-script/
##########

if [ $# -eq 0 ]
then
  echo "No arguments supplied. Expecting a file with a list of ILO-IPs/DNS names to connect to. E.g. run ./ilocheck.sh /tmp/ilo-list.txt"
  exit 1
fi

echo "Enter FULL AD-Account DN (required for ILO1/2) or local account name: (EX: CN=adminuser,OU=departmen1,OU=top,DC=domain,DC=local)"
read -e userdn
userdn64=$( echo -n $userdn | base64 -w 0 )
echo "Enter password:"
read -es pw
pw64=$( echo -n $pw | base64 -w 0 )

cat $@ | sort | while read ilo
do
  ilourl="https://$ilo"
  echo -e "\nChecking ILO Interface on $ilourl..."
  curl -ks "$ilourl" | if grep -Pq "HP Integrated Lights-Out( 2)? Login"
  then
    echo "$ilourl is an ILO2 or ILO1 System"
    curl -ks "$ilourl/login.htm" | grep -A1 "sessionkey=" | grep -Po '\w[^\"]+' > /tmp/ilotemp
    sessionkey=$( awk 'FNR == 2 {print}' /tmp/ilotemp )
    sessionindex=$( awk 'FNR == 4 {print}' /tmp/ilotemp )
    curl -ks "$ilourl/index.htm" --header "Cookie: hp-iLO-Login=$sessionindex:$userdn64:$pw64:$sessionkey" --header "Referer: $ilourl/login.htm" | if grep -q "has detected a failed login attempt"
    then
      echo "Login on $ilourl NOT successful."
    else
      echo "Login on $ilourl successful."
    fi

  else
    curl -ks "$ilourl" | if grep -Pq "iLO [34]"
    then
      echo "$ilourl is an ILO3 or ILO4 System"
      curl -ks "$ilourl/json/login_session" -X POST --data "{\"method\":\"login\",\"user_login\":\"$userdn\",\"password\":\"$pw\"}" | if grep -q "JS_ERR_NO_PRIV"
      then
        echo "Login on $ilourl NOT successful."
      else
        echo "Login on $ilourl successful."
      fi
    else
      echo "ILO Interface of $ilourl unreachable or not found"
    fi
  fi
done