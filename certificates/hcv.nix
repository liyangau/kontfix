{
  config,
  lib,
  sharedContext,
  ...
}:

with lib;

let
  cps = config.kontfix.controlPlanes;
  pkiCaCertConfig = config.kontfix.defaults.pki_ca_certificate;
  vaultPkiConfig = config.kontfix.defaults.vault_pki;
  # Use pre-computed collection from sharedContext
  hcvPkiPlanes = sharedContext.hcvPkiCertControlPlanes;
  # hcvPkiPlanes already has create_certificate = true, so pkiCreateCertControlPlanes is just hcvPkiPlanes
  pkiCreateCertControlPlanes = hcvPkiPlanes;
  pkiUploadCertControlPlanes = filterAttrs (name: cp: cp.upload_ca_certificate or true) hcvPkiPlanes;
  getEffectiveCaCertificate =
    cp:
    if cp.ca_certificate != null then
      cp.ca_certificate
    else if pkiCaCertConfig != null then
      pkiCaCertConfig
    else
      throw "PKI control plane requires ca_certificate to be set either on the control plane or as a global default (kontfix.defaults.pki_ca_certificate) when upload_ca_certificate is enabled";
in
{
  config = mkIf (cps != { }) {
    # Vault PKI client certificates for control planes
    resource.vault_pki_secret_backend_cert = mapAttrs (name: cp: {
      provider = "vault.pki";
      backend = vaultPkiConfig.backend;
      name = vaultPkiConfig.role_name;
      common_name = "konnect-${name}";
      ttl = vaultPkiConfig.ttl;
      auto_renew = vaultPkiConfig.auto_renew;
      min_seconds_remaining = vaultPkiConfig.min_seconds_remaining;
    }) pkiCreateCertControlPlanes;

    # PKI client certificates upload CA certificates
    resource.konnect_gateway_data_plane_client_certificate = mapAttrs (name: cp: {
      provider = "konnect.${cp.region}";
      cert = getEffectiveCaCertificate cp;
      control_plane_id = "\${konnect_gateway_control_plane.${name}.id}";
    }) pkiUploadCertControlPlanes;
  };
}
