
$thprefix=/home/ec2-user/termination
echo "=========================================================================="
echo "Deleting Old Files"
echo "=========================================================================="
echo "removing previosu env_name file"
echo "=========================================================================="
sudo rm -rf $pathprefix/env_name.txt
echo "removing old termination list"
echo "=========================================================================="
sudo rm -rf $pathprefix/terminate.txt
sudo rm -rf $pathprefix/output.txt
sudo rm -rf $pathprefix/env_name.txt
sudo rm -rf $pathprefix/termination.txt
sudo rm -rf $pathprefix/Alarmname.txt
sudo rm -rf $pathprefix/delenv.txt   
sudo rm -rf $pathprefix/final_env_list.txt 
sudo rm -rf $pathprefix/conclude.txt
while read app
do
/usr/bin/aws elasticbeanstalk describe-environments --region eu-west-1 --application-name "$app" | jq '.Environments[].EnvironmentName' | sed 's/["]//g' >> $pathprefix/env_name.txt
done < $pathprefix/application.txt
sleep 10s
for en in $(cat $pathprefix/env_name.txt)
do

envname=$(/usr/bin/aws elasticbeanstalk describe-environments --environment-name $en --region eu-west-1 | jq '.Environments[].Tier[]' | sed 's/["]//g' | sed -n '3p')
if [ "$envname" == "WebServer" ]
then
  {
  lbtype=$(/usr/bin/aws elasticbeanstalk describe-configuration-options --environment-name $en | grep "loadbalancer" -m1 | awk -F":" '{print $3}')
  if [ "$lbtype" == "elb" ];
  then
  {
          now="$(date +'%Y-%m-%dT%T')"
          starttime=$(date +'%Y-%m-%dT%T' --date '5 minutes ago')
          echo $en
          echo "Checking loadbalancer"
          lb=$(/usr/bin/aws elasticbeanstalk describe-environment-resources --environment-name $en | jq '.EnvironmentResources.LoadBalancers[].Name' | sed 's/["]//g')
          echo $lb
          echo "checking request"
	  sleep 10s
          request=$(/usr/bin/aws cloudwatch get-metric-statistics --metric-name RequestCount --start-time "$starttime"  --end-time "$now"  --period 300 --namespace AWS/ELB --statistics Sum --dimensions Name=LoadBalancerName,Value="$lb" | jq '.Datapoints[].Sum')
          echo $request
          if  [ -z "$request" ] || [ "$request" -lt "1" ];
          then
          echo $en >> $pathprefix/terminate.txt
          echo "adding to termination list"
          fi
          echo "=========================================================================="
  
  }
  else
  {
          now="$(date +'%Y-%m-%dT%T')"
          starttime=$(date +'%Y-%m-%dT%T' --date '5 minutes ago')
          echo  $en
          echo "Checking loadbalancer"
	  sleep 10s
          lb=$( /usr/bin/aws elasticbeanstalk describe-environment-resources --environment-name $en | jq '.EnvironmentResources.LoadBalancers[].Name'  | sed 's/^.*app/app/' | sed 's/["]//g')
          echo $lb
          echo "checking request"
	  sleep 10s
          request=$(/usr/bin/aws cloudwatch get-metric-statistics --metric-name RequestCount --start-time "$starttime"  --end-time "$now"  --period 300 --namespace AWS/ApplicationELB      --statistics Sum --dimensions Name=LoadBalancer,Value="$lb" | jq '.Datapoints[].Sum')
          echo $request
          if  [ -z "$request" ] || [ "$request" -lt "1" ];
          then
          echo $en >> $pathprefix/terminate.txt
          echo "adding to termination list"
          fi
          echo "=========================================================================="
  }
  fi
}
else
        echo $en
        echo "checking queue"
	sleep 10s
        queue=$(/usr/bin/aws elasticbeanstalk describe-environment-resources --environment-name  $en | jq '.EnvironmentResources.Queues[].URL' | sed -n '1p' | sed 's/["]//g' | awk -F"/" '{print $5}')
        if [[ "$queue" == *"dummy"* ]]
        then
        echo "queue is dummy"
        echo $en >> $pathprefix/terminate.txt
        echo $queue
        else
        echo "connected to prod : $queue"
        fi
        echo "=========================================================================="

fi
done
echo "**************************************************************************"
echo "Checking in Route53"
echo "**************************************************************************"

/usr/bin/aws route53 list-resource-record-sets --hosted-zone-id Z3QZNR0LDN71WU | grep "Value" | awk -F" " '{print $2}' | sed 's/["]//g' > $pathprefix/route_url.txt
for env_route in $(cat $pathprefix/terminate.txt)
do
{
	sleep 10s
        env_url=$(/usr/bin/aws elasticbeanstalk describe-environments --environment-names $env_route | jq '.Environments[].CNAME' | sed 's/["]//g')
        if grep -q $env_url "$pathprefix/route_url.txt";
        then
        echo "$env_route url exist in route53"
        else
        echo "adding $env_route enviroment for final check"
        echo $env_route >> $pathprefix/final_env_list.txt
        fi
}
done
echo "**************************************************************************"
echo "excluding friom list"
echo "**************************************************************************"

for env_route1 in $(cat $pathprefix/final_env_list.txt)
do
{
	sleep 10s
        env_url1=$(/usr/bin/aws elasticbeanstalk describe-environments --environment-names $env_route1 | jq '.Environments[].CNAME' | sed 's/["]//g')
        if grep -q $env_url1 "$pathprefix/exclude.txt";
        then
        echo "$env_route1 url exist in exclude list"
        else
        echo "adding $env_route1 enviroment for final check"
        echo $env_route1 >> $pathprefix/conclude.txt
        fi
}
done

