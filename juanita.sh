#!/bin/bash
#
# Pass two env vars:
#  - USER
#  - PASS

REST_SRV="https://bavl.lausanne.ch/iguana/Rest.Server.cls"

SESSION_ID=$(curl -s --cookie-jar cookies.txt 'https://bavl.lausanne.ch/iguana/www.main.cls' | grep "Vfocus.Settings.sessionID" | sed -e "s@.*Vfocus.Settings.sessionID = '\([^']*\)';.*@\1@")

IDENT=$(curl -s 'https://bavl.lausanne.ch/iguana/Rest.Server.cls?sessionId='${SESSION_ID}'&method=user/credentials' \
  -H 'Content-Type: application/json' \
  --cookie cookies.txt \
  --data-raw '{"request":{"language":"fre","serviceProfile":"Iguana","user":"'${USER}'","password":"'${PASS}'","institution":""}}')

NEW_SESSION_ID=$(jq -r '.response.sessionId' <<<$IDENT)


do_query() {
  local method="$1" data="$2"

  curl -s "${REST_SRV}?sessionId=${SESSION_ID}&method=${method}" \
    -H 'Content-Type: application/json' \
    --cookie cookies.txt \
    --data-raw $''${data}''
}

user_info() {
  do_query 'user/personaldata' '{"request":{"sessionId":"'$NEW_SESSION_ID'"}}'
}

list_loans() {
  info=$(user_info)
  name=$(jq -r '.response.name' <<<"$info")
  barcode=$(jq -r '.response.barcode' <<<"$info")

  echo -e "# ${name} (${barcode})\n\n"

  # Fetch the loans data
  loans=$(do_query 'user/loans' '{"request":{"sessionId":"'$NEW_SESSION_ID'","range":{"from":1,"to":50},"sort":{"sortBy":"\u0021DueDate","sortDirection":"ASC"}}}')

  # Check if there are any items
  item_count=$(echo "$loans" | jq '.response.items | length')

  if [ "$item_count" -gt 0 ]; then
    echo "$loans" | jq -r '
      def badge(status; date):
        if status == "OK" then "![OK](https://img.shields.io/badge/\(date)-ok-green.svg)"
        elif status == "NEEDS RENEWING" then "![Needs Renewing](https://img.shields.io/badge/\(date)-needs_renewing-orange.svg)"
        elif status == "LATE!" then "![Late](https://img.shields.io/badge/\(date)-late-red.svg)"
        elif status == "RENEWED" then "![Renewed](https://img.shields.io/badge/\(date)-renewed-green.svg)"
        elif status == "CANNOT RENEW!" then "![Cannot Renew](https://img.shields.io/badge/\(date)-cannot_renew-red.svg)"
        elif status == "FAILED RENEWING" then "![Failed Renewing](https://img.shields.io/badge/\(date)-failed_renewing-red.svg)"
        else "![Unknown](https://img.shields.io/badge/\(date)-unknown-lightgrey.svg)"
        end;

      def determine_status(dueDate):
        # Replace this logic with your own status determination logic
        if (now | strftime("%Y%m%d")) > dueDate then "LATE!" else "OK" end;

      .response.items[] | 
      .title as $title | 
      .dueDate as $dueDate |
      (determine_status($dueDate) as $status | badge($status; $dueDate)) as $badge | 
      "- \($badge) - \($title)"
    '
  else
    echo -e "**No books for this account**"
  fi

  echo -e "\n\n"
}


switch_user() {
  local user_id="$1"

  do_query 'user/switchuser' '{"request":{"sessionId":"'$NEW_SESSION_ID'","userId":"'${user_id}'"}}' > /dev/null
}


LINKED_ACCOUNTS=$(do_query 'user/linkedaccounts' '{"request":{"sessionId":"'$NEW_SESSION_ID'"}}')

OWN_ID=$(jq -r '.response.ownId' <<<$LINKED_ACCOUNTS)
USER_IDS=$(jq -r '.response.linkedAccounts[].id' <<<$LINKED_ACCOUNTS)

# Main user
list_loans

for user_id in $USER_IDS; do
  switch_user $user_id

  list_loans
  switch_user $OWN_ID
done
