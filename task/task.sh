
#!/bin/bash
set -eu
set +e
read -r -d '' iaas_configuration <<EOF
{
  "access_key_id": "$aws_access_key_id",
  "secret_access_key": "$aws_secret_access_key",
  "vpc_id": "$vpc_id",
  "security_group": "$pcf_security_group",
  "key_pair_name": "$AWS_KEY_NAME",
  "ssh_private_key": "$key_pair",
  "region": "$AWS_REGION",
  "encrypted": false
}
EOF

read -r -d '' director_configuration <<EOF
{
  "ntp_servers_string": "0.amazon.pool.ntp.org,1.amazon.pool.ntp.org,2.amazon.pool.ntp.org,3.amazon.pool.ntp.org",
  "resurrector_enabled": true,
  "max_threads": 30,
  "database_type": "external",
  "external_database_options": {
    "host": "$db_host",
    "port": 3306,
    "user": "$db_username",
    "password": "$rds_password",
    "database": "$db_database"
  },
  "blobstore_type": "s3",
  "s3_blobstore_options": {
    "endpoint": "https://s3.amazonaws.com",
    "bucket_name": "$s3_pcf_bosh",
    "access_key": "$aws_access_key_id",
    "secret_key": "$aws_secret_access_key",
    "signature_version": "4",
    "region": "$AWS_REGION"
  }
}
EOF

resource_configuration=$(cat <<-EOF
{
  "director": {
    "instance_type": {
      "id": "m4.large"
    }
  }
}
EOF
)

read -r -d '' az_configuration <<EOF
[
    { "name": "$az1" },
    { "name": "$az2" },
    { "name": "$az3" }
]
EOF

read -r -d '' networks_configuration <<EOF
{
  "icmp_checks_enabled": false,
  "networks": [
    {
      "name": "pcf-management-network",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$management_subnet_id_z1",
          "cidr": "$management_subnet_cidr_z1",
          "reserved_ip_ranges": "$management_subnet_reserved_ranges_z1",
          "dns": "$dns",
          "gateway": "$management_subnet_gw_z1",
          "availability_zone_names": ["$az1"]
        },
        {
          "iaas_identifier": "$management_subnet_id_z2",
          "cidr": "$management_subnet_cidr_z2",
          "reserved_ip_ranges": "$management_subnet_reserved_ranges_z2",
          "dns": "$dns",
          "gateway": "$management_subnet_gw_z2",
          "availability_zone_names": ["$az2"]
        },
        {
          "iaas_identifier": "$management_subnet_id_z3",
          "cidr": "$management_subnet_cidr_z3",
          "reserved_ip_ranges": "$management_subnet_reserved_ranges_z3",
          "dns": "$dns",
          "gateway": "$management_subnet_gw_z3",
          "availability_zone_names": ["$az3"]
        }
      ]
    },
    {
      "name": "pcf-pas-network",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$pas_subnet_id_z1",
          "cidr": "$pas_subnet_cidr_az1",
          "reserved_ip_ranges": "$pas_subnet_reserved_ranges_z1",
          "dns": "$dns",
          "gateway": "$pas_subnet_gw_z1",
          "availability_zone_names": ["$az1"]
        },
        {
          "iaas_identifier": "$pas_subnet_id_z2",
          "cidr": "$pas_subnet_cidr_az2",
          "reserved_ip_ranges": "$pas_subnet_reserved_ranges_z2",
          "dns": "$dns",
          "gateway": "$pas_subnet_gw_z2",
          "availability_zone_names": ["$az2"]
        },
        {
          "iaas_identifier": "$pas_subnet_id_z3",
          "cidr": "$pas_subnet_cidr_z3",
          "reserved_ip_ranges": "$pas_subnet_reserved_ranges_z3",
          "dns": "$dns",
          "gateway": "$pas_subnet_gw_z3",
          "availability_zone_names": ["$az3"]
        }
      ]
    },
    {
      "name": "pcf-services-network",
      "service_network": true,
      "subnets": [
        {
          "iaas_identifier": "$services_subnet_id_z1",
          "cidr": "$services_subnet_cidr_az1",
          "reserved_ip_ranges": "$services_subnet_reserved_ranges_z1",
          "dns": "$dns",
          "gateway": "$services_subnet_gw_z1",
          "availability_zone_names": ["$az1"]
        },
        {
          "iaas_identifier": "$services_subnet_id_z2",
          "cidr": "$services_subnet_cidr_z2",
          "reserved_ip_ranges": "$services_subnet_reserved_ranges_z2",
          "dns": "$dns",
          "gateway": "$subnet_gw_z2",
          "availability_zone_names": ["$az2"]
        },
        {
          "iaas_identifier": "$services_subnet_id_z3",
          "cidr": "$dynamic_services_subnet_cidr_z3",
          "reserved_ip_ranges": "$services_subnet_reserved_ranges_z3",
          "dns": "$dns",
          "gateway": "$services_subnet_gw_z3",
          "availability_zone_names": ["$az3"]
        }
      ]
    }
  ]
}
EOF

read -r -d '' network_assignment <<EOF
{
  "singleton_availability_zone": {
    "name": "$az1"
   },
  "network": {
    "name": "pcf-management-network"
  }
}
EOF

read -r -d '' security_configuration <<EOF
{
  "trusted_certificates": "",
  "vm_password_type": "generate"
}
EOF
set -e

iaas_configuration=$(echo "$iaas_configuration" |jq --arg ssh_private_key "$PEM" '.ssh_private_key = $ssh_private_key')

security_configuration=$(
  echo "$security_configuration" |
  jq --arg certs "$TRUSTED_CERTIFICATES" '.trusted_certificates = $certs'
)

jsons=(
  "$iaas_configuration"
  "$director_configuration"
  "$az_configuration"
  "$networks_configuration"
  "$network_assignment"
  "$security_configuration"
  "$resource_configuration"
)

for json in "${jsons[@]}"; do
  # ensure JSON is valid
  echo "$json" | jq '.'
done

om-linux \
  --target https://${OPSMAN_DOMAIN_OR_IP_ADDRESS} \
  --skip-ssl-validation \
  --username "$OPSMAN_USER" \
  --password "$OPSMAN_PASSWORD" \
  configure-director \
  --iaas-configuration "$iaas_configuration" \
  --director-configuration "$director_configuration" \
  --az-configuration "$az_configuration" \
  --networks-configuration "$networks_configuration" \
  --network-assignment "$network_assignment" \
  --security-configuration "$security_configuration" \
  --resource-configuration "$resource_configuration"
