{
  config,
  lib,
  utils,
  sharedContext,
  ...
}:

with lib;

let
  cps = config.kontfix.controlPlanes;
  selfSignedCertConfig = utils.validateSelfSignedCertConfig config.kontfix.defaults.self_signed_cert;
  pinnedCertControlPlanes = sharedContext.pinnedCertControlPlanes;
  pinnedCreateCertControlPlanes = filterAttrs (
    name: cp: cp.create_certificate
  ) pinnedCertControlPlanes;
  pinnedUploadCertControlPlanes = filterAttrs (
    name: cp: cp.upload_ca_certificate
  ) pinnedCertControlPlanes;
  getEffectiveCaCertificate =
    name: cp:
    if cp.ca_certificate != null then
      cp.ca_certificate # Explicit override
    else if cp.create_certificate then
      "\${tls_self_signed_cert.${name}.cert_pem}" # Generated self-signed
    else
      throw "Control plane '${name}' uses pinned_client_certs with create_certificate=false and upload_ca_certificate=true, but no ca_certificate is provided. Either set create_certificate=true, provide ca_certificate, or set upload_ca_certificate=false.";
in
{
  config = mkIf (cps != { }) {
    # Time rotation for certificate lifecycle management
    resource.time_rotating = mkIf (pinnedCreateCertControlPlanes != { }) (
      mapAttrs (name: cp: {
        rotation_days =
          selfSignedCertConfig.validity_period - selfSignedCertConfig.renewal_before_expiry;
      }) (mapAttrs' (name: cp: nameValuePair "${name}_cert" cp) pinnedCreateCertControlPlanes)
    );

    # Self-signed certificates for pinned cert control planes
    resource.tls_private_key = mkIf (pinnedCreateCertControlPlanes != { }) (
      mapAttrs (name: cp: {
        algorithm = "RSA";
        rsa_bits = 2048;
        lifecycle = [
          {
            replace_triggered_by = [
              "time_rotating.${name}_cert"
            ];
          }
        ];
      }) pinnedCreateCertControlPlanes
    );

    resource.tls_self_signed_cert = mkIf (pinnedCreateCertControlPlanes != { }) (
      mapAttrs (name: cp: {
        private_key_pem = "\${tls_private_key.${name}.private_key_pem}";
        subject = [
          {
            common_name = "konnect-${cp.region}-${cp.originalName}";
          }
        ];
        validity_period_hours = selfSignedCertConfig.validity_period * 24;
        allowed_uses = [
          "digital_signature"
          "key_encipherment"
          "client_auth"
          "server_auth"
        ];
        depends_on = [ "tls_private_key.${name}" ];
        lifecycle = [
          {
            replace_triggered_by = [
              "time_rotating.${name}_cert"
            ];
          }
        ];
      }) pinnedCreateCertControlPlanes
    );

    # Pinned client certificates for Konnect data planes (only when upload_ca_certificate = true)
    resource.konnect_gateway_data_plane_client_certificate =
      mkIf (pinnedUploadCertControlPlanes != { })
        (
          mapAttrs (
            name: cp:
            let
              effectiveCaCert = getEffectiveCaCertificate name cp;
            in
            {
              provider = "konnect.${cp.region}";
              cert = effectiveCaCert;
              control_plane_id = "\${konnect_gateway_control_plane.${name}.id}";
            }
          ) pinnedUploadCertControlPlanes
        );
  };
}