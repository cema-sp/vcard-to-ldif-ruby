# This script converts MS Exchange vCards \
# to iRedMail (OpenLDAP - Roundcube - SOGo) ldif and mail_users.csv
# Usage: ruby ms-vcard-to-ldif.rb ./vcards/ example.com
#   where example.com - target domain name

# Author: s.pisarev - s.a.pisarev@gmail.com

require 'securerandom'

## ---------------------------- Configuration --------------------------------
# 
CSV_FILE = './mail_users.csv'
LDIF_FILE = './30_vcards.ldif'
BASH_FILE = './send.sh'
VCARDS_DIR = ARGV[0]
DOMAIN_NEW = ARGV[1]

ldif_mapping = {
  'displayName' => 'full_name',
  'givenName' => 'first_name',
  'sn' => 'last_name',
  'o' => 'organization',
  'mobile' => 'phones',
  'telephoneNumber' => 'phones',
  'jpegPhoto:' => 'photo_base64'
}

ldif_description_templates = [
  'Birthdate: %s',
  'Emails: %s'
]

ldif_replace_keys = ['sn']

## ----------------------------- Methods -------------------------------------
# 
def to_utf_8(file_content)
  if charset = file_content.match('CHARSET\=(.*?)\:')
    file_content.
      encode(Encoding::UTF_8,
             charset[1],
             invalid: :replace)
  else
    file_content
  end
end

def user_from_vcard(vcard_file_text, user_domain)
  user = {
    'photo_base64' => ''
  }

  in_photo = false

  vcard_file_text.split($/).each do |vcard_file_line|
    parts = vcard_file_line.split(':')

    case parts.size
    when 1
      if !vcard_file_line.strip.empty? && in_photo
        user['photo_base64'] += vcard_file_line.strip
      end
    when 2
      tag = parts[0].split(';')[0]
      case tag
      when 'X-MS-CARDPICTURE'
        in_photo = true
      when 'FN'
        user['full_name'] = parts[1].strip
        user['first_name'], user['middle_name'], user['last_name'] = 
          parts[1].strip.split(' ')
      when 'ORG'
        user['organization'] = parts[1].strip
      when 'TEL'
        (user['phones'] ||= []) << parts[1].strip.gsub(/\s/,'')
      when 'EMAIL'
        (user['emails'] ||= []) << parts[1].strip
      when 'BDAY'
        user['birthday'] = parts[1].strip[6,2]
        user['birthmonth'] = parts[1].strip[4,2]
        user['birthyear'] = parts[1].strip[0,4]
      else
        in_photo = false
      end
    end
  end

  user['uid'] = user['emails'][0].split('@')[0]
  user['email_new'] = "#{user['uid']}@#{user_domain}"
  user['password'] = SecureRandom.urlsafe_base64(8)

  return user
end

def ldif_add_description(ldif, ldif_description_templates, *options)
  ldif['description'] = 
    ldif_description_templates.map do |template|
      option = options.shift
      if option.nil? || option.empty?
        nil
      else
        sprintf(template, option)
      end
    end.compact.join(', ')
end

def ldif_modify_header(user_email, user_domain)
  [
"dn: mail=#{user_email},
ou=Users,
domainName=#{user_domain},
o=domains,
dc=#{user_domain.split('.').join(',dc=')}".gsub(/\n/,''),
"changetype: modify"
  ].join("\n")
end

def ldif_body(ldif_fields, ldif_replace_keys)
  ldif_body_parts = []
  ldif_fields.each do |key, value|
    ldif_body_parts << 
      [
        (ldif_replace_keys.include?(key) ? 'replace' : 'add'),
        key.gsub(':','')
      ].join(': ')

    ldif_body_parts << 
      [
        key,
        (value.kind_of?(Array) ? value.join(', ') : value)
      ].join(': ')
  end

  ldif_body_parts.each_slice(2).map { |pair| pair.join("\n") }.join("\n-\n")
end

def make_bash_file(bash_file_path, domain_new, bash_file_params)
  File.open(bash_file_path, 'w+') do |bash_file|
    bash_file.puts %Q{\#!/bin/bash

CREDENTIALS=( 
 #{bash_file_params.join(" \n ")} 
)

OIFS=$IFS
for credsline in ${CREDENTIALS[@]}; do
  IFS=':'
  creds=($credsline)
  cat email.txt | sed 's/example.com/#{domain_new}/' | \\
    sed 's/emaillogin/'\"${creds[0]}\"'/' | \\
    sed 's/emailpassword/'\"${creds[1]}\"'/' | \\
    sed 's/emailaddresses/'\"${creds[2]}\"'/' | \\
    sendmail -FAdmin -fpostmaster@#{domain_new} -t
done
IFS=$OIFS
}
  end
end

def make_csv_file(csv_file_path, csv_lines)
  File.open(csv_file_path, 'w+') do |csv_file|
    csv_file.puts csv_lines.join("\n")
  end
end

def make_ldif_file(ldif_file_path, ldif_file_parts)
  File.open(ldif_file_path, 'w+') do |ldif_file|
    ldif_file.puts ldif_file_parts.join("\n\n")
  end
end

## ----------------------- Main ----------------------------------------------
#

bash_file_params = []
csv_lines = []
ldif_file_parts = []

Dir[VCARDS_DIR + "*"].each do |vcard_file_path|
  vcard_file_text = to_utf_8(File.binread(vcard_file_path))

  user = user_from_vcard(vcard_file_text, DOMAIN_NEW)

  ldif_fields =
    ldif_mapping.select{ |key, value|
      user.has_key?(value)
    }.inject({}) { |hash, (key, value)|
      hash.merge(key => user[value])
    }

  ldif_add_description(
    ldif_fields,
    ldif_description_templates,
    [
      user['birthday'],
      user['birthmonth'],
      user['birthyear']
    ].compact.join('.'),
    user['emails'].join(',')
    )

  ldif_file_parts << 
    [
      ldif_modify_header(user['email_new'],DOMAIN_NEW),
      ldif_body(ldif_fields, ldif_replace_keys)
    ].join("\n")

  # Empty parts for quota and qroups
  csv_lines <<
    [
      DOMAIN_NEW,
      user['uid'],
      user['password'],
      user['full_name'],
      '',
      ''
    ].join(', ')

  bash_file_params <<
    [
      user['email_new'],
      user['password'],
      user['emails'].join(',')
    ].join(':')
end

make_ldif_file(LDIF_FILE, ldif_file_parts)
make_csv_file(CSV_FILE, csv_lines)
make_bash_file(BASH_FILE, DOMAIN_NEW, bash_file_params)
