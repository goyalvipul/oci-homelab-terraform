#!/bin/bash

# LOG FILE
LOG_FILE="terraform_hunt.log"

echo "Starting Capacity Hunter for Phoenix (AD-1, AD-2, AD-3)..." > $LOG_FILE

while true; do
  # Loop through Availability Domains 1, 2, and 3
  for ad_num in 1 2 3; do
    echo "----------------------------------------------------" >> $LOG_FILE
    echo "[$(date)] 🔄 Switching to Availability Domain $ad_num..." >> $LOG_FILE
    
    # Use SED to edit the main.tf file in place
    # It looks for "ad_number = X" and replaces it with the current number
    sed -i -E "s/ad_number\s*=\s*[0-9]+/ad_number = $ad_num/" main.tf
    
    echo "[$(date)] 🚀 Attempting Terraform Apply in AD-$ad_num..." >> $LOG_FILE
    
    # Try to apply
    terraform apply -auto-approve >> $LOG_FILE 2>&1
    
    # Check if successful
    if [ $? -eq 0 ]; then
      echo "✅ SUCCESS! Infrastructure created in AD-$ad_num at $(date)" >> $LOG_FILE
      echo "✅ SUCCESS! Check $LOG_FILE for details."

      # We extract the IP from terraform outputs
      VM_IP=$(terraform output -raw vm_public_ip)
      
      MSG="🚨 SUCCESS! Oracle VM Created in AD-$ad_num.
      
      🌍 Public IP: $VM_IP
      
      #(Check your terminal for the Private Key if needed)"
      
      # 1. Log it locally
      echo "$MSG" >> $LOG_FILE
      echo "✅ SUCCESS! IP Found: $VM_IP"
      
      # 2. Send Telegram Message
      # Uses the token/chat_id defined at the top
      /home/vipulgoyal/telegram_bot/tg.sh "Instance Created Successfully "$VM_IP
     
      exit 0
    fi
    
    echo "⚠️  Failed in AD-$ad_num. Waiting 10 seconds before trying next AD..." >> $LOG_FILE
    sleep 10
  done

  echo "🛑 All ADs failed this round. Sleeping 60 seconds before restarting loop..." >> $LOG_FILE
  sleep 60
done
