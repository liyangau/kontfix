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

  # Cluster types
  clusterTypes = {
    controlPlane = "CLUSTER_TYPE_CONTROL_PLANE_GROUP";
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

  # ============================================================================
  # Helper Functions
  # ============================================================================

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

  # Filter control planes by certificate type
  filterByCertType =
    { controlPlanes, certType }:
    filterAttrs (name: cp: cp.create_certificate && cp.auth_type == certType) controlPlanes;

  # Filter control planes with individual system accounts
  filterIndividualSystemAccountPlanes =
    controlPlanes: filterAttrs (name: cp: cp.system_account.enable or false) controlPlanes;

  # Filter control planes with system account token generation enabled
  filterSystemAccountTokenPlanes =
    controlPlanes:
    filterAttrs (
      name: cp: cp.system_account.enable or false && cp.system_account.generate_token or false
    ) controlPlanes;

  # Filter control planes that require storage (certificate creation OR system account token generation)
  filterStorageRequiredControlPlanes =
    controlPlanes:
    filterAttrs (
      name: cp:
      cp.create_certificate or false
      || (cp.system_account.enable or false && cp.system_account.generate_token or false)
    ) controlPlanes;

  # Filter control planes by storage backend
  filterByStorageBackend =
    { controlPlanes, backend }: filterAttrs (name: cp: elem backend cp.storage_backend) controlPlanes;

  # Create all filtered collections for control planes to eliminate duplication
  createFilteredControlPlaneCollections =
    validatedControlPlanes:
    let
      # Certificate-based filters
      pkiCertControlPlanes = filterByCertType {
        controlPlanes = validatedControlPlanes;
        certType = authTypes.pki;
      };

      pinnedCertControlPlanes = filterByCertType {
        controlPlanes = validatedControlPlanes;
        certType = authTypes.pinned;
      };

      # Storage-based filters
      hcvStorageControlPlanes = filterByStorageBackend {
        controlPlanes = validatedControlPlanes;
        backend = "hcv";
      };

      awsStorageControlPlanes = filterByStorageBackend {
        controlPlanes = validatedControlPlanes;
        backend = "aws";
      };

      localStorageControlPlanes = filterByStorageBackend {
        controlPlanes = validatedControlPlanes;
        backend = "local";
      };

      awsStoragePkiCertControlPlanes = filterByCertType {
        controlPlanes = awsStorageControlPlanes;
        certType = authTypes.pki;
      };

      awsStoragePinnedCertControlPlanes = filterByCertType {
        controlPlanes = awsStorageControlPlanes;
        certType = authTypes.pinned;
      };
      awsStorageSysAccountControlPlanes = filterSystemAccountTokenPlanes awsStorageControlPlanes;

      hcvStoragePkiCertControlPlanes = filterByCertType {
        controlPlanes = hcvStorageControlPlanes;
        certType = authTypes.pki;
      };

      hcvStoragePinnedCertControlPlanes = filterByCertType {
        controlPlanes = hcvStorageControlPlanes;
        certType = authTypes.pinned;
      };

      hcvStorageSysAccountControlPlanes = filterSystemAccountTokenPlanes hcvStorageControlPlanes;

      localStoragePkiCertControlPlanes = filterByCertType {
        controlPlanes = localStorageControlPlanes;
        certType = authTypes.pki;
      };

      localStoragePinnedCertControlPlanes = filterByCertType {
        controlPlanes = localStorageControlPlanes;
        certType = authTypes.pinned;
      };

      localStorageSysAccountControlPlanes = filterSystemAccountTokenPlanes localStorageControlPlanes;

      # Other filters
      individualSystemAccountPlanes = filterIndividualSystemAccountPlanes validatedControlPlanes;
      outputEnabledControlPlanes = filterAttrs (_: cp: cp.output or false) validatedControlPlanes;

      # Storage requirement filter (using new function)
      storageRequiredControlPlanes = filterStorageRequiredControlPlanes validatedControlPlanes;

      # AWS-specific filters
      awsEnabledControlPlanes = filterAttrs (_: cp: cp.aws.enable or false) validatedControlPlanes;
      awsEnabledWithStorage = filterAttrs (
        name: cp: cp.aws.enable or false && elem "aws" cp.storage_backend
      ) validatedControlPlanes;
    in
    {
      inherit
        pkiCertControlPlanes
        pinnedCertControlPlanes
        hcvStorageControlPlanes
        awsStorageControlPlanes
        localStorageControlPlanes
        individualSystemAccountPlanes
        outputEnabledControlPlanes
        storageRequiredControlPlanes
        awsEnabledControlPlanes
        awsEnabledWithStorage
        awsStoragePkiCertControlPlanes
        awsStoragePinnedCertControlPlanes
        awsStorageSysAccountControlPlanes
        hcvStorageSysAccountControlPlanes
        hcvStoragePinnedCertControlPlanes
        hcvStoragePkiCertControlPlanes
        localStorageSysAccountControlPlanes
        localStoragePinnedCertControlPlanes
        localStoragePkiCertControlPlanes
        ;
    };

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
  # Validation Functions - Split into local and cross-cutting
  # ============================================================================

  # Local validation - only needs control plane data and peer references
  validateControlPlaneLocal =
    {
      name,
      cp,
      allControlPlaneNames,
    }:
    let
      isGroup = cp.cluster_type == clusterTypes.controlPlaneGroup;
      hasMembers = cp.members != [ ];

      # Validation 1: Control planes with members must be CLUSTER_TYPE_CONTROL_PLANE_GROUP
      membersTypeValid = !hasMembers || isGroup;

      # Validation 2: All members must be defined in the control planes list
      undefinedMembers = filter (member: !(elem member allControlPlaneNames)) cp.members;
      membersDefined = undefinedMembers == [ ];

      # Validation 3: Members of control plane groups must not have create_certificates = true
      invalidCertMembers = filter (
        member: allControlPlaneNames.${member}.create_certificate or false
      ) cp.members;
      membersCertValid = invalidCertMembers == [ ];

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
    in
    if !membersTypeValid then
      throw "Control plane '${cp.originalName}' has members ${toString cp.members} but its cluster_type is not ${clusterTypes.controlPlaneGroup}"
    else if !membersDefined then
      throw "Control plane group '${cp.originalName}' references undefined members: ${toString undefinedMembers}"
    else if !membersCertValid then
      throw "Control plane group '${cp.originalName}' member ${toString invalidCertMembers} has create_certificate = true"
    else if !groupSystemAccountValid then
      throw "Control plane group '${cp.originalName}' cannot have system_account.enable = true"
    else if !groupPluginsValid then
      throw "Control plane group '${cp.originalName}' cannot have custom_plugins defined."
    else if !awsTagsValid then
      throw "Control plane '${cp.originalName}' uses AWS backend but aws.tags is not defined or empty"
    else if !k8sAuthValid then
      throw "Control plane '${cp.originalName}' with cluster_type '${clusterTypes.k8sIngress}' must have auth_type '${authTypes.pinned}' but got '${cp.auth_type}'"
    else if !awsStorageValid then
      throw "Control plane '${cp.originalName}' uses AWS storage backend but aws.enable = false. Set aws.enable = true to use AWS storage."
    else if !regionValid then
      throw "Control plane '${cp.originalName}' has invalid region '${cp.region}'. Allowed regions are: ${concatStringsSep ", " allowedRegions}"
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
        cp.create_certificate or false
        || (cp.system_account.enable or false && cp.system_account.generate_token or false);
      usesHcvStorage = needsStorage && elem "hcv" cp.storage_backend;
      hcvStorageAddressValid = !usesHcvStorage || (defaults.storage.hcv.address or "") != "";

      # Validation 12: PKI control planes with create_certificate = true and pki_backend = "hcv" must have pki.hcv.address configured
      usesPkiAuth = cp.auth_type == authTypes.pki;
      createsCert = cp.create_certificate or false;
      usesHcvPki = usesPkiAuth && createsCert && cp.pki_backend == "hcv";
      hcvPkiAddressValid = !usesHcvPki || (defaults.pki.hcv.address or "") != "";
    in
    if !hcvStorageAddressValid then
      throw "Control plane '${name}' uses HCV storage backend but defaults.storage.hcv.address is not configured. Please set kontfix.defaults.storage.hcv.address"
    else if !hcvPkiAddressValid then
      throw "Control plane '${name}' uses HCV PKI backend but defaults.pki.hcv.address is not configured. Please set kontfix.defaults.pki.hcv.address"
    else
      cp;

  # Combined validation function
  validateControlPlane =
    {
      name,
      cp,
      allControlPlaneNames,
      defaults ? config.kontfix.defaults, # Default to config but allow override
    }:
    let
      locallyValidated = validateControlPlaneLocal { inherit name cp allControlPlaneNames; };
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
    in
    if !awsTagsValid then
      throw "Group '${group.groupName}' uses AWS backend but aws.tags is not defined or empty"
    else if !awsStorageValid then
      throw "Group '${group.groupName}' uses AWS storage backend but aws.enable = false. Set aws.enable = true to use AWS storage."
    else
      group;

  # ============================================================================
  # Processing Functions
  # ============================================================================

  # Comprehensive control plane processing utility
  processControlPlanes =
    {
      cps,
      defaultLabels ? { },
      validation ? true,
      defaults ? config.kontfix.defaults, # Explicit parameter for validation
    }:
    let
      flattenedControlPlanes = flattenControlPlanes cps;
      allControlPlaneNames = map (cp: cp.originalName) (builtins.attrValues flattenedControlPlanes);
      controlPlanesWithLabels = processControlPlanesWithLabels flattenedControlPlanes defaultLabels;

      # Apply validation if requested
      validatedControlPlanes =
        if validation then
          mapAttrs (
            name: cp:
            validateControlPlane {
              inherit
                name
                cp
                allControlPlaneNames
                defaults
                ;
            }
          ) controlPlanesWithLabels
        else
          controlPlanesWithLabels;
    in
    {
      inherit flattenedControlPlanes validatedControlPlanes allControlPlaneNames;
    }
    // createFilteredControlPlaneCollections validatedControlPlanes;

  # Helper function to convert validated groups back to groups structure for getGroupsWithStorage
  groupsFromValidated =
    validatedGroups:
    listToAttrs (
      map (group: {
        name = group.regionName;
        value = {
          ${group.originalName} = group.groupConfig;
        };
      }) validatedGroups
    );

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
      # Process control planes
      processed = processControlPlanes { inherit cps defaultLabels defaults; };

      # Process groups
      groupProcessed = processGroups { inherit groups; };
    in
    processed
    // createFilteredControlPlaneCollections processed.validatedControlPlanes
    // {
      # Add group-specific fields for easy access - use validated groups
      storageRequiredGroups = filter (
        group: group.groupConfig.generate_token
      ) groupProcessed.validatedGroups;
      awsStorageGroups = getGroupsWithStorage {
        groups = groupsFromValidated groupProcessed.validatedGroups;
        backend = "aws";
      };
      hcvStorageGroups = getGroupsWithStorage {
        groups = groupsFromValidated groupProcessed.validatedGroups;
        backend = "hcv";
      };
      localStorageGroups = getGroupsWithStorage {
        groups = groupsFromValidated groupProcessed.validatedGroups;
        backend = "local";
      };
      flattenedGroups = groupProcessed.flattenedGroups;
      validatedGroups = groupProcessed.validatedGroups;
    };

  # ============================================================================
  # Optimized Accessor Functions - Work with pre-computed context
  # ============================================================================

  # NEW: Functions that work with already-processed context (no re-processing)
  getControlPlanesFromContext = context: context.validatedControlPlanes;

  getCertificateControlPlanesFromContext =
    { context, authType }:
    if authType == authTypes.pki then
      context.pkiCertControlPlanes
    else if authType == authTypes.pinned then
      context.pinnedCertControlPlanes
    else
      throw "Invalid authType: ${authType}. Use '${authTypes.pki}' or '${authTypes.pinned}'.";

  getStorageControlPlanesFromContext =
    { context, backend }:
    let
      validBackends = [
        "hcv"
        "aws"
        "local"
      ];
    in
    if !(elem backend validBackends) then
      throw "Invalid storage backend '${backend}'. Supported backends: ${concatStringsSep ", " validBackends}"
    else if backend == "hcv" then
      context.hcvStorageControlPlanes
    else if backend == "aws" then
      context.awsStorageControlPlanes
    else if backend == "local" then
      context.localStorageControlPlanes
    else
      throw "Unexpected error with backend: ${backend}";

  getSystemAccountControlPlanesFromContext = context: context.individualSystemAccountPlanes;

  # DEPRECATED: Old functions that re-process (kept for backwards compatibility)
  # These should eventually be removed in favor of the *FromContext versions
  getControlPlanes = cps: (createSharedContext { inherit cps; }).validatedControlPlanes;

  getCertificateControlPlanes =
    { cps, authType }:
    getCertificateControlPlanesFromContext {
      context = createSharedContext { inherit cps; };
      inherit authType;
    };

  getStorageControlPlanes =
    { cps, backend }:
    getStorageControlPlanesFromContext {
      context = createSharedContext { inherit cps; };
      inherit backend;
    };

  getSystemAccountControlPlanes =
    cps: (createSharedContext { inherit cps; }).individualSystemAccountPlanes;

  # ============================================================================
  # Group Processing
  # ============================================================================

  processGroups =
    {
      groups,
      validation ? true,
    }:
    let
      flattenedGroups = flattenGroups groups;
      # Filter groups with token generation enabled (regardless of backend)
      storageRequiredGroups = filter (group: group.groupConfig.generate_token) flattenedGroups;
      # Apply validation if requested
      validatedGroups =
        if validation then
          map (group: validateGroup { inherit group; }) flattenedGroups
        else
          flattenedGroups;
    in
    {
      inherit flattenedGroups validatedGroups storageRequiredGroups;

      # Storage-specific filters using consolidated function
      awsStorageGroups = getGroupsWithStorage {
        groups = groups;
        backend = "aws";
      };

      hcvStorageGroups = getGroupsWithStorage {
        inherit groups;
        backend = "hcv";
      };

      localStorageGroups = getGroupsWithStorage {
        inherit groups;
        backend = "local";
      };
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

  getGroupsWithStorage =
    { groups, backend }:
    let
      flattened = flattenGroups groups;
      validBackends = [
        "hcv"
        "aws"
        "local"
      ];
      validBackend = elem backend validBackends;
    in
    if !validBackend then
      throw "Invalid storage backend '${backend}'. Supported backends: ${concatStringsSep ", " validBackends}"
    else
      filter (
        group: elem backend group.groupConfig.storage_backend && group.groupConfig.generate_token
      ) flattened;

  filterStorageRequiredGroups =
    groups:
    let
      flattened = flattenGroups groups;
    in
    filter (group: group.groupConfig.generate_token or false) flattened;

  # ============================================================================
  # Group Validation
  # ============================================================================

  validateGroups =
    { controlPlanes, groups }:
    let
      # Get all control plane names by region
      controlPlanesByRegion = mapAttrs (region: cps: attrNames cps) controlPlanes;

      # Validate each group
      validateGroup =
        region: groupName: group:
        let
          availableControlPlanes = controlPlanesByRegion.${region} or [ ];
          undefinedMembers = filter (member: !(elem member availableControlPlanes)) group.members;
        in
        if undefinedMembers != [ ] then
          throw "Group '${region}.${groupName}' references undefined control plane members: [${concatStringsSep ", " undefinedMembers}]. Available control planes in region '${region}': [${concatStringsSep ", " availableControlPlanes}]"
        else
          group;

      # Validate all groups in all regions
      validateAllGroups = mapAttrs (
        region: regionGroups: mapAttrs (groupName: group: validateGroup region groupName group) regionGroups
      ) groups;
    in
    validateAllGroups;

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
