{ lib, config }:

with lib;

rec {
  # ============================================================================
  # Constants - Centralized to eliminate hardcoded strings
  # ============================================================================

  # Authentication types
  authTypes = {
    pki = "pki_client_certs";
    pinned = "pinned_client_certs";
  };

  supportedPkiBackend = [
    "hcv"
  ];

  # Cluster types
  clusterTypes = {
    controlPlane = "CLUSTER_TYPE_CONTROL_PLANE";
    controlPlaneGroup = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
    k8sIngress = "CLUSTER_TYPE_K8S_INGRESS_CONTROLLER";
  };

  # Allowed regions
  allowedRegions = [
    "au"
    "us"
    "sg"
    "me"
    "eu"
    "in"
  ];

  # Supported storage backends
  supportedStorageBackends = [
    "hcv"
    "aws"
    "local"
  ];

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Returns null when the string is empty, otherwise the string itself.
  # Used to normalise optional config fields where null means "use Terraform variable".
  nullIfEmpty = s: if s != "" then s else null;

  # Single-pass tagging for O(n) performance
  # Tags control planes once, then filters become O(1) lookups
  tagControlPlanes =
    controlPlanes:
    mapAttrs (
      name: cp:
      let
        # Calculate all tags once per control plane
        hasPki = cp.auth_type == authTypes.pki;
        hasPinned = cp.auth_type == authTypes.pinned;
        createsCert = cp.create_certificate or false;
        systemAccountEnabled = cp.system_account.enable or false;
        systemAccountGenToken = cp.system_account.generate_token or false;
        usesHcv = elem "hcv" cp.storage_backend;
        usesAws = elem "aws" cp.storage_backend;
        usesLocal = elem "local" cp.storage_backend;
        usesHcvPki = (cp.pki_backend or "") == "hcv";
        awsEnabled = cp.aws.enable or false;
        isGroup = cp.cluster_type == clusterTypes.controlPlaneGroup;
        storesClusterConfig = cp.store_cluster_config or false;
        needsStorage =
          createsCert || storesClusterConfig || (systemAccountEnabled && systemAccountGenToken);
        
        # Normalize AWS region and profile: use cp.aws values if defined, otherwise fallback to variables
        # null means use var.aws_region or var.aws_profile
        computedAwsRegion = nullIfEmpty (cp.aws.region or "");
        computedAwsProfile = nullIfEmpty (cp.aws.profile or "");
      in
      cp
      // {
        # Store the computed AWS region and profile for use in storage backends and variable generation
        # If null, it means we should use var.aws_region or var.aws_profile in Terraform
        inherit computedAwsRegion computedAwsProfile;
        
        tags = {
          inherit
            hasPki
            hasPinned
            createsCert
            systemAccountEnabled
            systemAccountGenToken
            usesHcv
            usesAws
            usesLocal
            usesHcvPki
            awsEnabled
            isGroup
            needsStorage
            storesClusterConfig
            ;

          # Combined tags for common filter patterns
          pkiAndCert = hasPki && createsCert;
          pinnedAndCert = hasPinned && createsCert;
          systemAccountWithToken = systemAccountEnabled && systemAccountGenToken;
          awsStorageEnabled = usesAws && awsEnabled;
          clusterConfigOnly = storesClusterConfig && !createsCert;
          # PKI control planes that create certs using HCV PKI backend
          hcvPkiAndCert = hasPki && usesHcvPki && createsCert;
        };
      }
    ) controlPlanes;

  # Maps storage backend names to their corresponding tag names
  backendToStorageTag = {
    aws = "usesAws";
    hcv = "usesHcv";
    local = "usesLocal";
  };

  # Tag-based filtering functions (O(1) lookups after tagging)
  filterByTag =
    tag: taggedControlPlanes: filterAttrs (_: cp: cp.tags.${tag} or false) taggedControlPlanes;

  # Tag-based storage filtering with conditions
  filterByStorageTag =
    {
      taggedControlPlanes,
      backend,
      requireEnabled ? false,
    }:
    let
      tag = backendToStorageTag.${backend} or (throw "Unsupported storage backend: ${backend}");
    in
    filterAttrs (
      _: cp: cp.tags.${tag} && (if requireEnabled then cp.tags.awsEnabled else true)
    ) taggedControlPlanes;

  # Helper function to add provisioner and default labels
  addLabels =
    cp: defaultLabels:
    cp
    // {
      labels = cp.labels // defaultLabels;
    };

  # Process control planes with labels
  processControlPlanesWithLabels =
    cps: defaultLabels: mapAttrs (name: cp: addLabels cp defaultLabels) cps;

  # Create all filtered collections for control planes using tagged approach (O(1) lookups)
  createFilteredControlPlaneCollections =
    taggedValidatedControlPlanes:
    let
      pkiCertControlPlanes = filterByTag "pkiAndCert" taggedValidatedControlPlanes;
      pinnedCertControlPlanes = filterByTag "pinnedAndCert" taggedValidatedControlPlanes;
      individualSystemAccountPlanes = filterByTag "systemAccountEnabled" taggedValidatedControlPlanes;
      outputEnabledControlPlanes = filterAttrs (_: cp: cp.output or false) taggedValidatedControlPlanes;
      storageRequiredControlPlanes = filterByTag "needsStorage" taggedValidatedControlPlanes;
      awsProviderRequiredControlPlanes = filterAttrs (
        _: cp: cp.tags.usesAws || cp.tags.awsEnabled
      ) taggedValidatedControlPlanes;
      awsEnabledControlPlanes = filterByTag "awsEnabled" taggedValidatedControlPlanes;
      awsEnabledWithStorage = filterByTag "awsStorageEnabled" taggedValidatedControlPlanes;
      hcvPkiCertControlPlanes = filterByTag "hcvPkiAndCert" taggedValidatedControlPlanes;

      # Data-driven per-backend storage collections
      storageBackendConfigs = [
        { name = "hcv"; requireEnabled = false; }
        { name = "aws"; requireEnabled = true; }
        { name = "local"; requireEnabled = false; }
      ];
      storageSubTypes = [
        { suffix = "PkiCert"; tag = "pkiAndCert"; }
        { suffix = "PinnedCert"; tag = "pinnedAndCert"; }
        { suffix = "SysAccount"; tag = "systemAccountWithToken"; }
        { suffix = "ClusterConfigOnly"; tag = "clusterConfigOnly"; }
      ];

      # Base storage collections: hcvStorageControlPlanes, awsStorageControlPlanes, localStorageControlPlanes
      baseStorageCollections = listToAttrs (
        map (cfg: {
          name = "${cfg.name}StorageControlPlanes";
          value = filterByStorageTag {
            taggedControlPlanes = taggedValidatedControlPlanes;
            backend = cfg.name;
            requireEnabled = cfg.requireEnabled;
          };
        }) storageBackendConfigs
      );

      # Per-type collections: {backend}Storage{Type}ControlPlanes for each backend × type
      perTypeCollections = listToAttrs (
        concatMap (cfg:
          let base = baseStorageCollections."${cfg.name}StorageControlPlanes";
          in map (sub: {
            name = "${cfg.name}Storage${sub.suffix}ControlPlanes";
            value = filterByTag sub.tag base;
          }) storageSubTypes
        ) storageBackendConfigs
      );
    in
    {
      inherit
        pkiCertControlPlanes
        pinnedCertControlPlanes
        individualSystemAccountPlanes
        outputEnabledControlPlanes
        storageRequiredControlPlanes
        awsProviderRequiredControlPlanes
        awsEnabledControlPlanes
        awsEnabledWithStorage
        hcvPkiCertControlPlanes
        ;
    }
    // baseStorageCollections
    // perTypeCollections;

  # Core control plane processing functions
  flattenControlPlanes =
    regionCfg:
    lib.listToAttrs (
      lib.lists.flatten (
        lib.mapAttrsToList (
          region: planes:
          lib.mapAttrsToList (name: cp: {
            name = "${region}-${name}"; # Include region to make Terraform resource names unique
            value = cp // {
              inherit region;
              originalName = name; # Store original name for reference
            };
          }) planes
        ) regionCfg
      )
    );

  # ============================================================================
  # Group Validation - Prevent groups from referencing other groups
  # ============================================================================

  # Simple validation: Control plane groups can only reference individual control planes
  validateNoGroupReferences =
    allControlPlanes:
    let
      # Helper to find a control plane by original name
      findByOriginalName =
        originalName:
        let
          matches = filterAttrs (n: cp: (cp.originalName or "") == originalName) allControlPlanes;
        in
        if matches == { } then { } else head (attrValues matches);

      findGroupReferences = mapAttrsToList (
        name: cp:
        if cp.cluster_type == clusterTypes.controlPlaneGroup then
          let
            invalidMembers = filter (
              member:
              let
                memberCP = findByOriginalName member;
              in
              hasAttr "cluster_type" memberCP && memberCP.cluster_type == clusterTypes.controlPlaneGroup
            ) (cp.members or [ ]);
          in
          if invalidMembers != [ ] then [ { inherit name invalidMembers; } ] else [ ]
        else
          [ ]
      ) allControlPlanes;

      invalidReferences = concatLists findGroupReferences;
    in
    if invalidReferences != [ ] then
      let
        firstError = head invalidReferences;
        membersList = concatStringsSep ", " firstError.invalidMembers;
      in
      throw "Control plane group '${firstError.name}' can not have control plane groups '${membersList}' as its member. Groups members can only be individual control planes."
    else
      allControlPlanes;

  # ============================================================================
  # Validation Functions - Split into local and cross-cutting
  # ============================================================================

  # Local validation - only needs control plane data and peer references
  validateControlPlaneLocal =
    {
      name,
      cp,
      allControlPlanes, # Fixed: Pass the full attrset, not just names
    }:
    let
      # Extract original names from flattened control planes for validation
      allControlPlaneNames = map (cp: cp.originalName or cp.name) (attrValues allControlPlanes);
      isGroup = cp.cluster_type == clusterTypes.controlPlaneGroup;
      hasMembers = cp.members != [ ];

      # Validation 1: Control planes with members must be CLUSTER_TYPE_CONTROL_PLANE_GROUP
      membersTypeValid = !hasMembers || isGroup;

      # Validation 2: All members must be defined in the control planes list
      undefinedMembers = filter (member: !(elem member allControlPlaneNames)) cp.members;
      membersDefined = undefinedMembers == [ ];

      # Validation 3: Members of control plane groups must not have create_certificates = true or store_cluster_config = true
      # Helper to find a control plane by original name
      findByOriginalName =
        originalName:
        let
          matches = filterAttrs (n: cp: (cp.originalName or "") == originalName) allControlPlanes;
        in
        if matches == { } then { } else head (attrValues matches);

      invalidCertMembers = filter (
        member: (findByOriginalName member).create_certificate or false
      ) cp.members;
      membersCertValid = invalidCertMembers == [ ];

      invalidStoreConfigMembers = filter (
        member: (findByOriginalName member).store_cluster_config or false
      ) cp.members;
      membersStoreConfigValid = invalidStoreConfigMembers == [ ];

      # Validation 4: CLUSTER_TYPE_CONTROL_PLANE_GROUP must have system_account.enable = false
      groupSystemAccountValid = !isGroup || !(cp.system_account.enable or false);

      # Validation 5: CLUSTER_TYPE_CONTROL_PLANE_GROUP should not have custom_plugins
      groupPluginsValid = !isGroup || cp.custom_plugins == [ ];

      # Validation 6: Control planes using AWS backend must have aws.tags defined
      usesAws = elem "aws" cp.storage_backend;
      awsTagsValid = !usesAws || (cp ? aws && cp.aws ? tags && cp.aws.tags != { });

      # Validation 7: K8s Ingress Controller must use pinned_client_certs
      k8sAuthValid = cp.cluster_type != clusterTypes.k8sIngress || cp.auth_type == authTypes.pinned;

      # Validation 8: AWS storage backend requires aws.enable = true
      usesAwsStorage = elem "aws" cp.storage_backend;
      awsEnabled = cp.aws.enable or false;
      awsStorageValid = !usesAwsStorage || awsEnabled;

      # Validation 9: Region must be in allowed list
      regionValid = elem cp.region allowedRegions;

      # Validation 10: PKI control planes with create_certificate = true must have a supported pki_backend
      usesPkiAuth = cp.auth_type == authTypes.pki;
      createsCert = cp.create_certificate or false;
      pkiBackendValid = !usesPkiAuth || !createsCert || (elem cp.pki_backend supportedPkiBackend);
    in
    if !membersTypeValid then
      throw "Control plane '${cp.originalName}' has members ${toString cp.members} but cluster_type is not CLUSTER_TYPE_CONTROL_PLANE_GROUP"
    else if !membersDefined then
      throw "Control plane group '${cp.originalName}' references undefined members: ${toString undefinedMembers}"
    else if !membersCertValid then
      throw "Control plane group '${cp.originalName}' member ${toString invalidCertMembers} has create_certificate = true"
    else if !membersStoreConfigValid then
      throw "Control plane group '${cp.originalName}' member ${toString invalidStoreConfigMembers} has store_cluster_config = true"
    else if !groupSystemAccountValid then
      throw "Control plane group '${cp.originalName}' cannot have system_account.enable = true"
    else if !groupPluginsValid then
      throw "Control plane group '${cp.originalName}' cannot have custom_plugins defined."
    else if !awsTagsValid then
      throw "Control plane '${cp.originalName}' uses AWS backend but aws.tags is not defined or empty"
    else if !k8sAuthValid then
      throw "Control plane '${cp.originalName}' with cluster_type 'CLUSTER_TYPE_K8S_INGRESS_CONTROLLER' must have auth_type 'pinned_client_certs' but got '${cp.auth_type}'"
    else if !awsStorageValid then
      throw "Control plane '${cp.originalName}' uses AWS storage backend but aws.enable = false. Set aws.enable = true to use AWS storage."
    else if !regionValid then
      throw "Control plane '${cp.originalName}' has invalid region '${cp.region}'. Allowed regions are: ${concatStringsSep ", " allowedRegions}"
    else if !pkiBackendValid then
      throw "Control plane '${cp.originalName}' has unsupported pki_backend '${cp.pki_backend}'. Supported backends: ${concatStringsSep ", " supportedPkiBackend}"
    else
      cp;

  # Cross-cutting validation - requires global defaults configuration
  validateControlPlaneWithDefaults =
    {
      name,
      cp,
      defaults, # Explicitly pass just the defaults we need
    }:
    let
      # Validation 11: Control planes that need storage and use HCV backend must have storage.hcv.address configured
      needsStorage =
        (cp.create_certificate or false)
        || (cp.store_cluster_config or false)
        || ((cp.system_account.enable or false) && (cp.system_account.generate_token or false));
      usesHcvStorage = needsStorage && elem "hcv" cp.storage_backend;
      hcvStorageAddressValid = !usesHcvStorage || (defaults.storage.hcv.address or "") != "";

      # Validation 12: PKI control planes with create_certificate = true and pki_backend = "hcv" must have pki.hcv.address configured
      usesPkiAuth = cp.auth_type == authTypes.pki;
      createsCert = cp.create_certificate or false;
      usesHcvPki = usesPkiAuth && createsCert && cp.pki_backend == "hcv";
      hcvPkiAddressValid = !usesHcvPki || (defaults.pki.hcv.address or "") != "";
    in
    if !hcvStorageAddressValid then
      throw "Control plane '${cp.originalName}' uses HCV storage backend but defaults.storage.hcv.address is not configured. Please set kontfix.defaults.storage.hcv.address"
    else if !hcvPkiAddressValid then
      throw "Control plane '${cp.originalName}' uses HCV PKI backend but defaults.pki.hcv.address is not configured. Please set kontfix.defaults.pki.hcv.address"
    else
      cp;

  # Combined validation function
  validateControlPlane =
    {
      name,
      cp,
      allControlPlanes, # Fixed: Pass full attrset
      defaults ? config.kontfix.defaults, # Default to config but allow override
    }:
    let
      locallyValidated = validateControlPlaneLocal { inherit name cp allControlPlanes; };
    in
    validateControlPlaneWithDefaults {
      inherit name defaults;
      cp = locallyValidated;
    };

  # ============================================================================
  # Group Validation Functions
  # ============================================================================

  # Group validation function - validates AWS configuration for groups
  validateGroup =
    {
      group, # group object with regionName, groupName, groupConfig
    }:
    let
      groupConfig = group.groupConfig;
      # Validation 1: Groups using AWS backend must have aws.tags defined
      usesAws = elem "aws" groupConfig.storage_backend;
      awsTagsValid =
        !usesAws || (groupConfig ? aws && groupConfig.aws ? tags && groupConfig.aws.tags != { });

      # Validation 2: Groups using AWS backend must have aws.enable = true
      awsEnabled = groupConfig.aws.enable or false;
      awsStorageValid = !usesAws || awsEnabled;

      # Compute AWS region and profile (null if not defined)
      computedAwsRegion = nullIfEmpty (groupConfig.aws.region or "");
      computedAwsProfile = nullIfEmpty (groupConfig.aws.profile or "");
    in
    if !awsTagsValid then
      throw "Group '${group.originalName}' uses AWS backend but aws.tags is not defined or empty"
    else if !awsStorageValid then
      throw "Group '${group.originalName}' uses AWS storage backend but aws.enable = false. Set aws.enable = true to use AWS storage."
    else
      group // { inherit computedAwsRegion computedAwsProfile; };

  # ============================================================================
  # Processing Functions
  # ============================================================================

  # Comprehensive control plane processing utility
  processControlPlanes =
    {
      cps,
      defaultLabels ? { },
      defaults ? config.kontfix.defaults,
    }:
    let
      flattenedControlPlanes = flattenControlPlanes cps;
      allControlPlaneNames = map (cp: cp.originalName) (builtins.attrValues flattenedControlPlanes);
      controlPlanesWithLabels = processControlPlanesWithLabels flattenedControlPlanes defaultLabels;

      # Validate: check group references first, then individual control planes
      planesWithoutGroupReferences = validateNoGroupReferences controlPlanesWithLabels;
      validatedControlPlanes = mapAttrs (
        name: cp:
        validateControlPlane {
          inherit name cp defaults;
          allControlPlanes = planesWithoutGroupReferences;
        }
      ) planesWithoutGroupReferences;

      # Tag validated control planes for O(1) filtering
      taggedValidatedControlPlanes = tagControlPlanes validatedControlPlanes;
    in
    {
      inherit
        flattenedControlPlanes
        validatedControlPlanes
        allControlPlaneNames
        taggedValidatedControlPlanes
        ;
    }
    // createFilteredControlPlaneCollections taggedValidatedControlPlanes;

  # ============================================================================
  # Shared Context - Process once, use many times
  # ============================================================================

  # Create shared context that gets passed around instead of re-processing
  createSharedContext =
    {
      cps,
      groups ? { },
      defaultLabels ? { },
      defaults ? config.kontfix.defaults,
    }:
    let
      # Process control planes once with tagging
      processed = processControlPlanes { inherit cps defaultLabels defaults; };

      # Process groups once
      groupProcessed = processGroups { inherit groups; };
    in
    processed
    // {
      # Group-specific fields (computed only when accessed)
      storageRequiredGroups = filter (
        group: group.groupConfig.generate_token
      ) groupProcessed.validatedGroups;
      # Filter validated groups directly to preserve computed fields
      awsStorageGroups = filter (
        group: 
          elem "aws" group.groupConfig.storage_backend 
          && group.groupConfig.generate_token
          && (group.groupConfig.aws.enable or false)
      ) groupProcessed.validatedGroups;
      hcvStorageGroups = filter (
        group: 
          elem "hcv" group.groupConfig.storage_backend 
          && group.groupConfig.generate_token
      ) groupProcessed.validatedGroups;
      localStorageGroups = filter (
        group: 
          elem "local" group.groupConfig.storage_backend 
          && group.groupConfig.generate_token
      ) groupProcessed.validatedGroups;
      flattenedGroups = groupProcessed.flattenedGroups;
      validatedGroups = groupProcessed.validatedGroups;
    };

  # ============================================================================
  # Group Processing
  # ============================================================================

  processGroups =
    { groups }:
    let
      flattenedGroups = flattenGroups groups;
      validatedGroups = map (group: validateGroup { inherit group; }) flattenedGroups;
      storageRequiredGroups = filter (group: group.groupConfig.generate_token) flattenedGroups;
    in
    {
      inherit flattenedGroups validatedGroups storageRequiredGroups;
    };

  flattenGroups =
    groups:
    flatten (
      mapAttrsToList (
        regionName: regionGroups:
        mapAttrsToList (groupName: groupConfig: {
          inherit regionName;
          groupName = "${regionName}-${groupName}";
          inherit groupConfig;
          originalName = groupName; # Store original name for reference
        }) regionGroups
      ) groups
    );

  # Generates the cluster topology fields shared across all storage backends.
  # Returns a Nix string fragment to embed in a secret_string / data_json block.
  # Covers: cluster_prefix, cluster_control_plane, cluster_server_name,
  #   cluster_telemetry_endpoint, cluster_telemetry_server_name
  # Plus private_* fields when awsRegionExpr is provided.
  makeClusterConfigFields =
    {
      name,
      region,
      awsRegionExpr ? null,
    }:
    let
      cpPfx = "regex(\"^https://([^.]+)\\\\.\", konnect_gateway_control_plane.${name}.config.control_plane_endpoint)[0]";
      baseFields = [
        "cluster_prefix = ${cpPfx}"
        "cluster_control_plane = \"\${${cpPfx}}.${region}.cp.konghq.com:443\""
        "cluster_server_name = \"\${${cpPfx}}.${region}.cp.konghq.com\""
        "cluster_telemetry_endpoint = \"\${${cpPfx}}.${region}.tp.konghq.com:443\""
        "cluster_telemetry_server_name = \"\${${cpPfx}}.${region}.tp.konghq.com\""
      ];
      privateFields = optionals (awsRegionExpr != null) [
        "private_cluster_url = \"\${substr(${awsRegionExpr}, 0, 2)}.svc.konghq.com/cp/\${${cpPfx}}\""
        "private_telemetry_url = \"\${substr(${awsRegionExpr}, 0, 2)}.svc.konghq.com:443/tp/\${${cpPfx}}\""
        "private_cluster_server_name=\"\${substr(${awsRegionExpr}, 0, 2)}.svc.konghq.com\""
        "private_cluster_telemetry_server_name=\"\${substr(${awsRegionExpr}, 0, 2)}.svc.konghq.com\""
      ];
    in
    concatStringsSep "\n          " (baseFields ++ privateFields);

  # Validation function for self-signed certificate configuration
  validateSelfSignedCertConfig =
    selfSignedCertConfig:
    if selfSignedCertConfig.validity_period <= 0 then
      throw "kontfix.defaults.self_signed_cert.validity_period must be greater than 0, got ${toString selfSignedCertConfig.validity_period}"
    else if selfSignedCertConfig.renewal_before_expiry <= 0 then
      throw "kontfix.defaults.self_signed_cert.renewal_before_expiry must be greater than 0, got ${toString selfSignedCertConfig.renewal_before_expiry}"
    else if selfSignedCertConfig.validity_period <= selfSignedCertConfig.renewal_before_expiry then
      throw "kontfix.defaults.self_signed_cert.validity_period (${toString selfSignedCertConfig.validity_period}) must be greater than renewal_before_expiry (${toString selfSignedCertConfig.renewal_before_expiry})"
    else
      selfSignedCertConfig;
}
