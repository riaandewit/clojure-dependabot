#!/bin/bash

update_package () {
    if [[ $3 == "project.clj" ]]; then
        clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M -m antq.core --upgrade --force --directory "$1" --focus="$2" --skip=clojure-cli
    else
        clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M -m antq.core --upgrade --force --directory "$1" --focus="$2" --skip=leiningen
    fi
    git checkout -b "dependabot/clojure${1/$GITHUB_WORKSPACE}/$4-$5-$3-$6"
    git add "$3"
    git commit -m "Bump $2"
    git push --set-upstream origin "dependabot/clojure${1/$GITHUB_WORKSPACE}/$4-$5-$3-$6"
    echo "Bump $2 $7 to $5"
    if [[ $8 != "null" ]]; then
        gh pr create -B "$INPUT_MAIN_BRANCH" --title "Bump $2 from $7 to $5" -b "Bumps **$2** from $7 to $5.</br>*Changelog:* $8.$9</br></br>---</br></br>Pull request generated by Github Action \"Dependabot for Clojure projects\". Auto-rebase is currently not supported, so it is recommended to rebase before merging to prevent conflicts." -l "$INPUT_LABELS" -r "$INPUT_REVIEWERS"
    else
        gh pr create -B "$INPUT_MAIN_BRANCH" --title "Bump $2 from $7 to $5" -b "Bumps **$2** from $7 to $5.$9</br></br>---</br></br>Pull request generated by Github Action \"Dependabot for Clojure projects\". Auto-rebase is currently not supported, so it is recommended to rebase before merging to prevent conflicts." -l "$INPUT_LABELS" -r "$INPUT_REVIEWERS"
    fi
    git checkout "$INPUT_MAIN_BRANCH"
}

# https://gist.github.com/jonlabelle/6691d740f404b9736116c22195a8d706
version_ge() { 
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; 
}
version_gt() { 
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; 
}

high_critical_check_security_fix () {
    newDependencies=()
    tempGhAlerts=("$@")
    cd "$2" || exit
    for alertGh in "${tempGhAlerts[@]:2}"
    do
        if [[ "$INPUT_VERBOSE" == true ]]; then
            echo "newDependencies array: ${newDependencies[*]}"
            echo "Checking the first-level dep $1"
            echo "$alertGh"
        fi
        IFS='|' read -r -a array_alertGh <<< "$alertGh"
        if [[ "$INPUT_UPDATE_OMITTED" == false ]]; then
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Update omitted packages: false"
            fi   
            if [[ "${array_alertGh[4]}" == "$1" ]]; then
                afterUpdateVersion=$(mvn -ntp dependency:tree -DoutputType=dot -Dincludes="${array_alertGh[0]}" | grep -e "->" | cut -d ">" -f 2 | cut -d '"' -f 2 | grep -e "${array_alertGh[0]}" | cut -d ":" -f 4)
                if [[ "$INPUT_VERBOSE" == true ]]; then
                    echo "Checking available security updates for ${array_alertGh[0]}. Current: ${array_alertGh[3]} Latest: $afterUpdateVersion"
                fi
                if version_ge "$afterUpdateVersion" "${array_alertGh[3]}"; then
                    if [[ ! "${newDependencies[*]}" == *"${array_alertGh[0]}|$afterUpdateVersion|"* ]]; then
                        newDependencies+=("${array_alertGh[0]}|$afterUpdateVersion|")
                        if [[ "$INPUT_VERBOSE" == true ]]; then
                            echo "${array_alertGh[0]}|$afterUpdateVersion|"
                        fi
                    fi
                fi
                if [ -z "$afterUpdateVersion" ]; then
                    if [[ ! "${newDependencies[*]}" == *"${array_alertGh[0]}|removed|"* ]]; then
                        newDependencies+=("${array_alertGh[0]}|removed|")
                        if [[ "$INPUT_VERBOSE" == true ]]; then
                            echo "${array_alertGh[0]}|removed|"
                        fi
                    fi
                fi
            fi
        else
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Update omitted packages: true"
            fi
            tempDependencyTree=$(mvn -ntp dependency:tree -Dincludes="${array_alertGh[0]}" -Dverbose)
            tempFirstLevelDependencies=$(echo "$tempDependencyTree" | grep -e "\\\-" -e "\+\-" | grep -v -e "\s\s\\\-" -e "\s\s+\-" | cut -d "-" -f 2-100)
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Checking available security updates for ${array_alertGh[0]}. First patched version: ${array_alertGh[3]}"
                echo "First-level dependencies for ${array_alertGh[0]}"
                echo "$tempFirstLevelDependencies"
            fi
            IFS=$'\n' read -d '' -r -a firstLevelDependencies <<< "$tempFirstLevelDependencies"
            if [[ "${array_alertGh[5]}" == *"$1"* ]]; then
                if [[ "${firstLevelDependencies[*]}" == *"$1"* ]]; then
                    for ii in "${!firstLevelDependencies[@]}"; do
                        if [[ "${firstLevelDependencies[$ii]}" == *"$1"* ]]; then
                            if [[ ${ii} -eq ${#firstLevelDependencies[@]} ]]; then
                                firstLevDep=$(cut -d':' -f1-2 <<<"${firstLevelDependencies[$ii]}")
                                tempAfterUpdateVersions=$(echo "$tempDependencyTree" | sed -n "/$firstLevDep/,//p" | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                    echo "Versions after update for ${array_alertGh[0]} in $1"
                                    echo "$tempAfterUpdateVersions"
                                fi                                
                                IFS=$'\n' read -d '' -r -a AfterUpdateVersions <<< "$tempAfterUpdateVersions"
                                for jj in "${!AfterUpdateVersions[@]}"; do
                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                        echo "${array_alertGh[0]} version_ge (AfterUpdateVersions > first_patched_version): ${AfterUpdateVersions[$jj]} >= ${array_alertGh[3]}"
                                    fi 
                                    if (version_ge "${AfterUpdateVersions[$jj]}" "${array_alertGh[3]}"  && [[ ! "${newDependencies[*]}" == *"${array_alertGh[0]}|${AfterUpdateVersions[$j]}|"* ]]); then
                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                            echo "version_ge() passed"
                                        fi 
                                        tempPreviousDependencyTree=$(cd previous || exit; mvn -ntp dependency:tree -Dincludes="${array_alertGh[0]}" -Dverbose)
                                        tempPreviousFirstLevelDependencies=$(echo "$tempPreviousDependencyTree" | grep -e "\\\-" -e "\+\-" | grep -v -e "\s\s\\\-" -e "\s\s+\-" | cut -d "-" -f 2-100)
                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                            echo "First-level dependencies for ${array_alertGh[0]} in /previous/pom.xml."
                                            echo "$tempPreviousFirstLevelDependencies"
                                        fi
                                        IFS=$'\n' read -d '' -r -a previousFirstLevelDependencies <<< "$tempPreviousFirstLevelDependencies"
                                        for kk in "${!previousFirstLevelDependencies[@]}"; do
                                            if [[ "$INPUT_VERBOSE" == true ]]; then
                                                previousFirstLevDep=$(cut -d':' -f1-2 <<<"${previousFirstLevelDependencies[$kk]}")
                                                echo "previousFirstLevelDependencies: $previousFirstLevDep"
                                                echo "firstLevelDependencies: $firstLevDep"
                                            fi
                                            if [[ "$previousFirstLevDep" == "$firstLevDep" ]]; then
                                                if [[ ${kk} -eq ${#previousFirstLevelDependencies[@]} ]]; then      
                                                    tempBeforeUpdateVersions=$(echo "$tempPreviousDependencyTree" | sed -n "/$previousFirstLevDep/,//p" | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                                else
                                                    previousFirstLevDepNext=$(cut -d':' -f1-2 <<<"${previousFirstLevelDependencies[(( $kk+1 ))]}")
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "firstLevelDependenciesNext: $previousFirstLevDepNext"
                                                    fi
                                                    tempBeforeUpdateVersions=$(echo "$tempPreviousDependencyTree" | sed -n "/$previousFirstLevDep/,/$previousFirstLevDepNext/p" | sed '$d' | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                                fi
                                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                                    echo "Versions for ${array_alertGh[0]} in $1 in previous/pom.xml"
                                                    echo "$tempBeforeUpdateVersions"
                                                fi                                
                                                IFS=$'\n' read -d '' -r -a BeforeUpdateVersions <<< "$tempBeforeUpdateVersions"
                                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                                    echo "Length BeforeUpdateVersions: ${#BeforeUpdateVersions[@]}"
                                                    echo "Length AfterUpdateVersions: ${#AfterUpdateVersions[@]}"
                                                fi
                                                if [[ ${#BeforeUpdateVersions[@]} -eq ${#AfterUpdateVersions[@]} ]]; then
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "${array_alertGh[0]} version_gt (first_patched_version > BeforeUpdateVersions): ${array_alertGh[3]} > ${BeforeUpdateVersions[$jj]}"
                                                    fi 
                                                    if version_gt "${array_alertGh[3]}" "${BeforeUpdateVersions[$jj]}"; then
                                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                                            echo "version_gt() passed"
                                                        fi                                                         
                                                        newDependencies+=("${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|")
                                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                                            echo "${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|"
                                                        fi
                                                        break 2
                                                    fi
                                                else
                                                    newDependencies+=("${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|")
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|"
                                                    fi
                                                    break 2                                               
                                                fi
                                            fi
                                        done
                                    fi
                                done
                            else
                                firstLevDep=$(cut -d':' -f1-2 <<<"${firstLevelDependencies[$ii]}")
                                firstLevDepNext=$(cut -d':' -f1-2 <<<"${firstLevelDependencies[(( $ii+1 ))]}")
                                tempAfterUpdateVersions=$(echo "$tempDependencyTree" | sed -n "/$firstLevDep/,/$firstLevDepNext/p" | sed '$d' | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                    echo "Versions after update for ${array_alertGh[0]} in $1"
                                    echo "$tempAfterUpdateVersions"
                                fi  
                                IFS=$'\n' read -d '' -r -a AfterUpdateVersions <<< "$tempAfterUpdateVersions"
                                for jj in "${!AfterUpdateVersions[@]}"; do
                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                        echo "${array_alertGh[0]} version_ge (AfterUpdateVersions > first_patched_version): ${AfterUpdateVersions[$jj]} >= ${array_alertGh[3]}"
                                    fi  
                                    if (version_ge "${AfterUpdateVersions[$jj]}" "${array_alertGh[3]}" && [[ ! "${newDependencies[*]}" == *"${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|"* ]]); then
                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                            echo "version_ge() passed"
                                        fi                                         
                                        tempPreviousDependencyTree=$(cd previous || exit; mvn -ntp dependency:tree -Dincludes="${array_alertGh[0]}" -Dverbose)
                                        tempPreviousFirstLevelDependencies=$(echo "$tempPreviousDependencyTree" | grep -e "\\\-" -e "\+\-" | grep -v -e "\s\s\\\-" -e "\s\s+\-" | cut -d "-" -f 2-100)
                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                            echo "First-level dependencies for ${array_alertGh[0]} in /previous/pom.xml."
                                            echo "$tempPreviousFirstLevelDependencies"
                                        fi
                                        IFS=$'\n' read -d '' -r -a previousFirstLevelDependencies <<< "$tempPreviousFirstLevelDependencies"
                                        for kk in "${!previousFirstLevelDependencies[@]}"; do
                                            if [[ "$INPUT_VERBOSE" == true ]]; then
                                                previousFirstLevDep=$(cut -d':' -f1-2 <<<"${previousFirstLevelDependencies[$kk]}")
                                                echo "previousFirstLevelDependencies: $previousFirstLevDep"
                                                echo "firstLevelDependencies: $firstLevDep"
                                            fi
                                            if [[ "$previousFirstLevDep" == "$firstLevDep" ]]; then
                                                if [[ ${kk} -eq ${#previousFirstLevelDependencies[@]} ]]; then
                                                    tempBeforeUpdateVersions=$(echo "$tempPreviousDependencyTree" | sed -n "/$previousFirstLevDep/,//p" | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                                else
                                                    previousFirstLevDepNext=$(cut -d':' -f1-2 <<<"${previousFirstLevelDependencies[(( $kk+1 ))]}")
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "firstLevelDependenciesNext: $previousFirstLevDepNext"
                                                    fi
                                                    tempBeforeUpdateVersions=$(echo "$tempPreviousDependencyTree" | sed -n "/$previousFirstLevDep/,/$previousFirstLevDepNext/p" | sed '$d' | grep -e "\\\-" -e "\+\-" | grep -e "${array_alertGh[0]}" | awk -F "${array_alertGh[0]}:jar:" '{print $2; printf $100}' | cut -f1 -d ":")
                                                fi
                                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                                    echo "Versions for ${array_alertGh[0]} in $1 in previous/pom.xml"
                                                    echo "$tempBeforeUpdateVersions"
                                                fi                                
                                                IFS=$'\n' read -d '' -r -a BeforeUpdateVersions <<< "$tempBeforeUpdateVersions"
                                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                                    echo "Length BeforeUpdateVersions: ${#BeforeUpdateVersions[@]}"
                                                    echo "Length AfterUpdateVersions: ${#AfterUpdateVersions[@]}"
                                                fi
                                                if [[ ${#BeforeUpdateVersions[@]} -eq ${#AfterUpdateVersions[@]} ]]; then
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "${array_alertGh[0]} version_gt (first_patched_version > BeforeUpdateVersions): ${array_alertGh[3]} > ${BeforeUpdateVersions[$jj]}"
                                                    fi 
                                                    if version_gt "${array_alertGh[3]}" "${BeforeUpdateVersions[$jj]}"; then
                                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                                            echo "version_gt() passed"
                                                        fi
                                                        newDependencies+=("${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|")
                                                        if [[ "$INPUT_VERBOSE" == true ]]; then
                                                            echo "${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|"
                                                        fi
                                                        break 2
                                                    fi
                                                else
                                                    newDependencies+=("${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|")
                                                    if [[ "$INPUT_VERBOSE" == true ]]; then
                                                        echo "${array_alertGh[0]}|${AfterUpdateVersions[$jj]}|"
                                                    fi
                                                    break 2                                               
                                                fi
                                            fi
                                        done
                                    fi
                                done
                            fi
                        fi
                    done
                else
                    if [[ ! "${newDependencies[*]}" == *"${array_alertGh[0]}|removed|"* ]]; then
                        if [[ "$INPUT_VERBOSE" == true ]]; then
                            echo "${array_alertGh[0]}|removed|"
                        fi
                        newDependencies+=("${array_alertGh[0]}|removed|")
                    fi
                fi
            fi
        fi
    done
}

vulnerability_fix_pr () {
    tempNewDependencies=("$@")
    if [ ${#tempNewDependencies[@]} -eq 0 ]; then
        securityUpdatesPrBody=""
    else
        securityUpdatesPrBody="</br></br>**Security updates**"
        for newDep in "${tempNewDependencies[@]}"
        do
            IFS='|' read -r -a array_newDep <<< "$newDep"
            if [[ "${array_newDep[1]}" == "removed" ]]; then
                securityUpdatesPrBody+="</br>Removed dependency ${array_newDep[0]}"
            else
                securityUpdatesPrBody+="</br>Updated dependency ${array_newDep[0]} to version ${array_newDep[1]}"
            fi
        done
    fi
}

# $1 - "project.clj" or "deps.edn"
if [[ -n $INPUT_DIRECTORY ]]; then
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Moving to $GITHUB_WORKSPACE$INPUT_DIRECTORY"
    fi
    cd "$GITHUB_WORKSPACE$INPUT_DIRECTORY" || exit
fi
if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Finding all $1 files"
fi
mapfile -t array < <(find . -name "$1")
if [[ $1 == "project.clj" ]]; then
    echo "## Outdated Dependencies" >> "$GITHUB_STEP_SUMMARY"
fi
if [[ $INPUT_INCLUDE_SUBDIRECTORIES != true ]]; then
    if [[ $1 == "project.clj" ]] && [[ "${array[*]}" == *"./project.clj"* ]]; then
        array=("./project.clj")
    elif [[ $1 == "deps.edn" ]] && [[ "${array[*]}" == *"./deps.edn"* ]]; then
        array=("./deps.edn")
    else
        array=()
    fi
fi
for i in "${array[@]}"
do
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Working on $i"
    fi
    summaryOutput=0
    counterDuplicate=""
    i=${i/.}
    cljdir=$GITHUB_WORKSPACE$INPUT_DIRECTORY${i//\/$1}
    cd "$cljdir" || exit
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Creating antq-report.json"
    fi
    clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M -m antq.core --reporter="json" > /tmp/antq-report.json || true
    length=$(jq '. | length' /tmp/antq-report.json)
    length=$((length-1))
    githubAlerts=()
    vul_page=$(cat /tmp/dependabot_alerts.json)
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "$vul_page"
    fi
    if  [[ $1 == "project.clj" ]]; then
        pomManifestPath="$cljdir/projectclj" || exit
    else
        pomManifestPath="$cljdir/depsedn" || exit
    fi
    mkdir "/${pomManifestPath:1}/previous"
    cp "/${pomManifestPath:1}/pom.xml" "/${pomManifestPath:1}/previous/pom.xml"
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Copy pom.xml to folder 'previous'"
        ls "/${pomManifestPath:1}/previous"
    fi
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Checking GitHub Security alerts for $i"
    fi
    mapfile -t tempGithubAlerts < <(jq -r --arg MANIFEST "${pomManifestPath:1}/pom.xml" '.[] | select(.dependency.manifest_path == $MANIFEST and .state == "open") | .security_vulnerability.package.name + "|" + .security_vulnerability.severity + "|" + .security_advisory.ghsa_id + "|" + .security_vulnerability.first_patched_version.identifier + "|"' <<< "${vul_page}")
    for vulPackage in "${tempGithubAlerts[@]}"
    do
        IFS='|' read -r -a array_vulnPackage <<< "$vulPackage"
        if [[ $INPUT_SEVERITY == "low" ]]; then
            severityLevel="low|medium|high|critical"
        elif [[ $INPUT_SEVERITY == "medium" ]]; then
            severityLevel="medium|high|critical"
        elif [[ $INPUT_SEVERITY == "high" ]]; then
            severityLevel="high|critical"
        elif [[ $INPUT_SEVERITY == "critical" ]]; then
            severityLevel="critical"
        else
            severityLevel="medium|high|critical"
        fi
        if [[ "$severityLevel" == *"${array_vulnPackage[1]}"* ]]; then
            cd "$pomManifestPath" || exit
            dep_level=$(mvn -ntp dependency:tree -DoutputType=dot -Dincludes="${array_vulnPackage[0]}" | grep -e "->" | cut -d ">" -f 2 | cut -d '"' -f 2 | cut -d ":" -f 1-2)
            IFS=' ' read -r -a dependency_level <<< "$dep_level"
            vulPackage+="${dependency_level[0]}|"
            tempFirstLevelDependencies=$(mvn -ntp dependency:tree -Dincludes="${array_vulnPackage[0]}" -Dverbose | grep -e "\\\-" -e "\+\-" | grep -v -e "\s\s\\\-" -e "\s\s+\-" | cut -d "-" -f 2-100)
            IFS=$'\n' read -d '' -r -a firstLevelDependencies <<< "$tempFirstLevelDependencies"
            vulPackage+="${firstLevelDependencies[*]}|"
            githubAlerts+=("$vulPackage")
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "$vulPackage"
            fi
        fi
    done
    cd "$cljdir" || exit
    # required for high_critical_check_security_fix() to not duplicate operations
    clojure -Sdeps '{:deps {com.github.liquidz/antq {:mvn/version "RELEASE"}}}' -M -m antq.core --upgrade --force --skip=clojure-cli --skip=leiningen --directory="$pomManifestPath"
    if [[ "$INPUT_VERBOSE" == true ]]; then
        echo "Checking available security updates for $i"
    fi
    for j in $(seq 0 $length);
    do
        fileType=$(jq -r ".[$j] .file" /tmp/antq-report.json)
        if  [[ $fileType == "$1" ]]; then
            name=$(jq -r ".[$j] .name" /tmp/antq-report.json)
            version=$(jq -r ".[$j] .version" /tmp/antq-report.json)
            latestVersion=$(jq -r ".[$j] .\"latest-version\"" /tmp/antq-report.json)
            changesUrl=$(jq -r ".[$j] .\"changes-url\"" /tmp/antq-report.json)
            time=$(date +%s)
            escapedName=$(echo "$name" | tr "/" "-")
            namePom=$(echo "$name" | tr "/" ":")
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Package: $name Current: $version Latest: $latestVersion"
            fi
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Running high_critical_check_security_fix()"
            fi
            high_critical_check_security_fix "$namePom" "$pomManifestPath" "${githubAlerts[@]}"
            cd "$cljdir" || exit
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "${newDependencies[*]}"
            fi
            if [ ${#newDependencies[@]} -eq 0 ]; then
                securityUpdate=""
            else
                securityUpdate="⬆️"
            fi
            prefix="dependabot/clojure${cljdir/$GITHUB_WORKSPACE}/$escapedName-$latestVersion-$1-"
            if [[ "$summaryOutput" -eq 0 ]]; then
                {
                    echo "### $INPUT_DIRECTORY$i"
                    echo "<details>"
                    echo ""
                    echo "| Dependency | From | To | Changelog | Security |"
                    echo "| --- | --- | --- | --- | --- |"
                } >> "$GITHUB_STEP_SUMMARY"
                summaryOutput=1
            fi
            if [[ "$INPUT_VERBOSE" == true ]]; then
                echo "Adding info to GitHub Summary"
            fi            
            if [[ $counterDuplicate != *"| $name | $version | $latestVersion | [🔗 Changelog]($changesUrl) | $securityUpdate |"* ]]; then
                if [[ $changesUrl == "null" ]]; then
                    echo "| $name | $version | $latestVersion |  | $securityUpdate |" >> "$GITHUB_STEP_SUMMARY"
                    if [[ "$INPUT_VERBOSE" == true ]]; then
                        echo echo "| $name | $version | $latestVersion |  | $securityUpdate |"
                    fi
                else
                    echo "| $name | $version | $latestVersion | [🔗 Changelog]($changesUrl) | $securityUpdate |" >> "$GITHUB_STEP_SUMMARY"
                    if [[ "$INPUT_VERBOSE" == true ]]; then
                        echo "| $name | $version | $latestVersion | [🔗 Changelog]($changesUrl) | $securityUpdate |"
                    fi                
                fi
                counterDuplicate+="| $name | $version | $latestVersion | [🔗 Changelog]($changesUrl) | $securityUpdate |"
            fi
            if [[ $INPUT_AUTO_PULL_REQUEST == true ]] && [[ ! "$INPUT_IGNORE_DEPENDENCY" == *"$name"* ]]; then
                if [[ "$INPUT_VERBOSE" == true ]]; then
                    echo "Running vulnerability_fix_pr()"
                fi
                vulnerability_fix_pr "${newDependencies[@]}"
                if [[ $INPUT_SECURITY_UPDATES_ONLY == true ]]; then
                    if [ -n "$securityUpdate" ]; then
                        git fetch
                        mapfile -t branches < <(git branch -r | grep "$prefix")
                        if [[ ${branches[*]} ]]; then
                            prTime=()
                            for k in "${branches[@]}"
                            do
                                prTime+=("${k//origin\/$prefix/}")
                            done
                            IFS=" " read -r -a lastBranch <<< "$(echo "${prTime[*]}" | xargs -n1 | sort -nr | xargs)"
                            if [[ "$INPUT_VERBOSE" == true ]]; then
                                echo "Checking if the security update PR already exists"
                            fi
                            statusPr=$(gh pr list --head "$prefix${lastBranch[0]}" --state open --json title | jq ". | length")
                            if [[ $statusPr -lt 1 ]]; then
                                if [[ "$INPUT_VERBOSE" == true ]]; then
                                    echo "Create the security PR dependabot/clojure${cljdir/$GITHUB_WORKSPACE}/$escapedName-$latestVersion-$1-$time"
                                fi
                                update_package "$cljdir" "$name" "$1" "$escapedName" "$latestVersion" "$time" "$version" "$changesUrl" "$securityUpdatesPrBody"
                            else
                                git checkout "$INPUT_MAIN_BRANCH"
                            fi
                        else
                            if [[ "$INPUT_VERBOSE" == true ]]; then
                                echo "Create the security PR dependabot/clojure${cljdir/$GITHUB_WORKSPACE}/$escapedName-$latestVersion-$1-$time"
                            fi
                            update_package "$cljdir" "$name" "$1" "$escapedName" "$latestVersion" "$time" "$version" "$changesUrl" "$securityUpdatesPrBody"
                        fi    
                    fi
                else
                    git fetch
                    mapfile -t branches < <(git branch -r | grep "$prefix")
                    if [[ ${branches[*]} ]]; then
                        prTime=()
                        for k in "${branches[@]}"
                        do
                            prTime+=("${k//origin\/$prefix/}")
                        done
                        IFS=" " read -r -a lastBranch <<< "$(echo "${prTime[*]}" | xargs -n1 | sort -nr | xargs)"
                        if [[ "$INPUT_VERBOSE" == true ]]; then
                            echo "Checking if the security update PR already exists"
                        fi
                        statusPr=$(gh pr list --head "$prefix${lastBranch[0]}" --state open --json title | jq ". | length")
                        if [[ $statusPr -lt 1 ]]; then
                            if [[ "$INPUT_VERBOSE" == true ]]; then
                                echo "Create the security PR dependabot/clojure${cljdir/$GITHUB_WORKSPACE}/$escapedName-$latestVersion-$1-$time"
                            fi
                            update_package "$cljdir" "$name" "$1" "$escapedName" "$latestVersion" "$time" "$version" "$changesUrl" "$securityUpdatesPrBody"
                        else
                            git checkout "$INPUT_MAIN_BRANCH"
                        fi
                    else
                        if [[ "$INPUT_VERBOSE" == true ]]; then
                            echo "Create the security PR dependabot/clojure${cljdir/$GITHUB_WORKSPACE}/$escapedName-$latestVersion-$1-$time"
                        fi
                        update_package "$cljdir" "$name" "$1" "$escapedName" "$latestVersion" "$time" "$version" "$changesUrl" "$securityUpdatesPrBody"
                    fi
                fi
            fi
        fi
    done
    if [[ "$summaryOutput" -eq 1 ]]; then
        echo "</details>" >> "$GITHUB_STEP_SUMMARY"
        echo "" >> "$GITHUB_STEP_SUMMARY"
    fi
done