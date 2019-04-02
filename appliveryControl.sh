#!/bin/bash
####################################
#Created by Yaroslav Nevmerzhytskyi#
####################################
######## Variables ########
accountApiKey=""
appId=""
authorizationPattern=""
buildList=""
sortedBuilds=""
menuList="Menu:\n1)ListBuilds\n2)GetBuildDescription\n3)Upload\n4)DeleteBuilds\n5)Quit\n"
########----END----########

######## Functions ########
function tryInstallJq()
{
	printf "Checking if jq is installed...\n"
	
	$(command -v jq >/dev/null 2>&1 || { printf >&2 "Installing jq...\n"; $(brew install jq); })

	printf "Jq is installed...\n"
	return 0
}

function readAccountApiKey()
{
	read -p "Copy Account API Key from Developers menu on Applivery and paste it here: " accountApiKey
	if [[ "$accountApiKey" == "" ]]; then
		readAccountApiKey
	fi

	return 0
}

function readAndSetAppId()
{
	read -p "Copy App ID from desired application's details on Applivery and paste it here: " appId
	if [[ "$appId" == "" ]]; then
		readAndSetAppId
	else
		readAccountApiKey
		status=""
		{
			authorizationPattern="Authorization:$accountApiKey"
			request="https://dashboard.applivery.com/api/builds/app/$appId"
			response=$(curl "$request" -H "$authorizationPattern")

			if $(checkStatus "$response"); then
		    	status=""
		    else
		    	status="Wrong App ID or Account API Key provided. Please try again\n"
		    fi
		} &> /dev/null

		if [[ "$status" != "" ]]; then
			printf "$status\n"
			readAndSetAppId
			return 1
		fi

		echo "export APPLIVERY_APP_ID=$appId" >>~/.bash_profile
		echo "export APPLIVERY_ACCOUNT_API_KEY=$accountApiKey" >>~/.bash_profile
		source ~/.bash_profile
		printf "Setup finished.\n\n\n\nPlease restart the terminal...\n"
		exit
	fi

	return 0
}

function init()
{
	appId=$(printenv APPLIVERY_APP_ID)
	
	if [[ "$appId" == "" ]]; then
		readAndSetAppId
		return 1
	fi

	accountApiKey=$(printenv APPLIVERY_ACCOUNT_API_KEY)
	authorizationPattern="Authorization:$accountApiKey"

	return 0
}

function checkStatus()
{
	statusObject=$1
	status=$(echo "$statusObject" | jq '.status')
	echo "$status"
	if [[ "$status" == "true" ]]; then
		return 0
	fi

	return 1
}

function getErrorStatus()
{
	statusObject=$1
	message=$(echo "$statusObject" | jq '(.error.code | tostring) + ": " + .error.msg')
	echo "$message"

	return 0
}

function sortBuildsByDate()
{
	printf "Sorting buildList...\n"

	sortedBuilds=$(echo "$buildList" | jq 'sort_by(.modified | match("^[0-9T:-]+[^.]") | .string + "Z"| fromdate)')

	return 0
}

function uploadToApplivery()
{
	printf "Sorry, kind NotImplemented exception has been thrown :)\n"
	return 1

	versionName="$1"
	notes="$2"
	if [[ "$3" == "y" ]]; then
		shouldNotify="true"
	else
		shouldNotify="false"
	fi
	platform="$4"
	tags="$5"
	buildPath="$6"

	printf "Preparing to upload build...\n \
		Parameters[versionName:$versionName, notes:$notes, notify:$notify, \
		platform:$platform, tags:$tags, buildPath:$buildPath"

	request="https://dashboard.applivery.com/api/builds"
    response=$(curl "$request" \
    	-X POST \
    	-H "$authorizationPattern"
	    -F app="$appId" \
	    -F versionName="$versionName" \
	    -F notes="$notes" \
	    -F notify="$shouldNotify" \
	    -F os="$platform" \
	    -F tags="$tags" \
	    -F package=@"$buildPath")
    
    if $(checkStatus "$response"); then
    	printf "Build successfully uploaded...\n"
    else
    	error=$(getErrorStatus "$response")
    	printf "Build uploading failed... Error: $error\n"
    	return 1
    fi

    return 0
}

function listBuilds()
{
	#global var buildList

	suppressLogs=$1
	if [[ "$suppressLogs" == "" ]]; then
		suppressLogs="false"
	else
		suppressLogs="true"
	fi

	printf "Requesting build list...\n"
	
	request="https://dashboard.applivery.com/api/builds/app/$appId"
	response=$(curl "$request" -H "$authorizationPattern")

	if $(checkStatus "$response"); then
		amount=$(echo "$response" | jq '.response | length')
    	printf "$amount Builds received...\n"
    	buildList=$(echo "$response" | jq '.response')
    	if [[ "$suppressLogs" == "false" ]]; then
    		log=$(echo "$buildList" | jq -r '.[] | "ID: " + ._id + "; Modified: " + .modified + "; Name: " + .versionName')
    		printf "%s\n" "$log"
    		printf "$amount builds in total.\n"
    	fi
    else
    	error=$(getErrorStatus "$response")
    	printf "Failed to get builds list... Error: $error\n"
    	return 1
    fi

	return 0
}

function getBuildInformation()
{
	buildId=$1

	printf "Getting build information...\n"
	
	request="https://dashboard.applivery.com/api/builds/$buildId"
	response=$(curl "$request" -H "$authorizationPattern")

	if $(checkStatus "$response"); then
    	printf "Builds information received...\n"
    	buildInfo=$(echo "$response" | jq -r '.')
    	printf "%s\n" "$buildInfo"
    else
    	error=$(getErrorStatus "$response")
    	printf "Failed to get build's information. Check validity of the buildID... Error: $error\n"
    	return 1
    fi

	return 0
}

function deleteBuild()
{
	toRemove=$1

	printf "Starting build deletion...\n"

	listBuilds "suppressLogs"
	sortBuildsByDate

	buildIds=$(echo "$sortedBuilds" | jq --arg toRemove $toRemove '.[0:($toRemove | tonumber)] | .[]._id')

	for buildId in $buildIds
	do
		buildId=$(echo "$buildId" | tr -d '"')
		
		modified=$(echo "$sortedBuilds" | jq --arg buildId $buildId '.[] | select(._id == $buildId) | .modified')
		versionName=$(echo "$sortedBuilds" | jq --arg buildId $buildId '.[] | select(._id == $buildId) | .versionName')
		read -p "You're about to remove build {ID: $buildId, Modified: $modified, Name: $versionName}. ARE YOU SURE?([y]/n):" verification

		if [[ "$verification" == "n" ]]; then
			printf "Skipping deletion of build ID:$buildId..."
			continue
		fi

		request="https://dashboard.applivery.com/api/builds/$buildId"
		response=$(curl "$request" \
		-X DELETE \
		-H "$authorizationPattern")
		sleep 1

		if $(checkStatus "$response"); then
	    	printf "Build with ID $buildId had been deleted...\n"
	    else
	    	error=$(getErrorStatus "$response")
	    	printf "Failed to delete build with ID $buildId... Error: $error\n"
	    	return 1
	    fi
	done

	return 0
}
########----END----########

######## Main flow ########

tryInstallJq
init

menu="Select action:"
select action in ListBuilds GetBuildDescription Upload DeleteBuilds Quit
do
	case $action in
		ListBuilds)
			command=$(listBuilds)
			printf "$command\n$menuList";;
		GetBuildDescription)
			read -p "Enter build ID? " answer
			command=$(getBuildInformation $answer)
			printf "$command\n$menuList";;
		Upload)
			read -p "Enter Version name: " versionName
			read -p "Enter notes: " notes
			read -p "Enter shouldNotify([n]/y): " shouldNotify
			read -p "Enter platform: " platform
			read -p "Enter tags: " tags
			read -p "Enter buildPath: " buildPath
			command=$(uploadToApplivery $versionName $notes $shouldNotify $platform $tags $buildPath)
			printf "$command\n$menuList";;
		DeleteBuilds)
			read -p "How many? " answer
			command=$(deleteBuild $answer)
			printf "$command\n$menuList";;
		Quit)
			break;;
	esac
done

########----END----########
