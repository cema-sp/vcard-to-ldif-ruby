# MS vCards -> LDIF converter

This script converts MS Exchange vCards to:  

* [iRedMail]-compatible *(OpenLDAP - Roundcube - SOGo)* LDIF;
* mail_users.csv *(domain, uid, password, cn, , )* - CSV file with users
* send.sh - bash script for mailing users

# Requirements

* [Ruby]

# Usage

## Generate files

Run it with following command structure:  
```bash
ruby ms-vcard-to-ldif.rb ./vcards/ example.com
```

Where *example.com* - target domain name, 
*./vcards* - directory containing vCards.  

The script outputs result to current directory.  

## Send emails

Before mailing you should edit file *email.txt*.  
To perform mailing run following command on mail server:  

```bash
bash send.sh
```

[Ruby]: https://www.ruby-lang.org "Ruby"
[iRedMail]: http://www.iredmail.org/ "iRedMail"
