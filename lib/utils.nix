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
        awsEnabled = cp.aws.enable or false;
        isGroup = cp.cluster_type == clusterTypes.controlPlaneGroup;
        needsStorage = createsCert || (systemAccountEnabled && systemAccountGenToken);
      in
      cp
      // {
        _tags = {
          inherit
            hasPki
            hasPinned
            createsCert
            systemAccountEnabled
            systemAccountGenToken
            usesHcv
            usesAws
            usesLocal
            awsEnabled
            isGroup
            needsStorage
            ;

          # Combined tags for common filter patterns
          pkiAndCert = hasPki && createsCert;
          pinnedAndCert = hasPinned && createsCert;
          systemAccountWithToken = systemAccountEnabled && systemAccountGenToken;
          awsStorageEnabled = usesAws && awsEnabled;
        };
      }
    ) controlPlanes;

  # Tag-based filtering functions (O(1) lookups after tagging)
  filterByTag =
    tag: taggedControlPlanes: filterAttrs (_: cp: cp._tags.${tag} or false) taggedControlPlanes;

  # Tag-based storage filtering with conditions
  filterByStorageTag =
    {
      taggedControlPlanes,
      backend,
      requireEnabled ? false,
    }:
    filterAttrs (
      _: cp:
      if backend == "aws" then
        cp._tags.usesAws && (if requireEnabled then cp._tags.awsEnabled else true)
      else if backend == "hcv" then
        cp._tags.usesHcv
      else if backend == "local" then
        cp._tags.usesLocal
      else
        false
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

  # Generic filter builder for storage backends with optional enabled flag
  makeStorageFilter =
    {
      backend,
      requireEnabled ? false,
      requireStorage ? true,
    }:
    filterAttrs (
      name: cp:
      (if requireStorage then elem backend cp.storage_backend else true)
      && (if requireEnabled then (cp.${backend}.enable or false) else true)
    );

  # Filter control planes by storage backend
  filterByStorageBackend =
    { controlPlanes, backend }: makeStorageFilter { inherit backend; } controlPlanes;

  # Filter control planes by AWS storage backend AND aws.enable = true
  filterByAwsStorageWithEnabledFlag = makeStorageFilter {
    backend = "aws";
    requireEnabled = true;
  };

  # Filter control planes that need AWS providers (either use AWS storage OR have aws.enable = true)
  filterByAwsProviderRequired = filterAttrs (
    name: cp: elem "aws" cp.storage_backend || (cp.aws.enable or false)
  );

  # Generic filter combinator to reduce duplication
  combineFilters = filters: controlPlanes: foldl' (acc: filter: filter acc) controlPlanes filters;

  # Helper to create storage + cert type filters
  createStorageCertFilters = storageBackend: controlPlanes: {
    pkiCert = filterByCertType {
      controlPlanes = storageBackend;
      certType = authTypes.pki;
    };
    pinnedCert = filterByCertType {
      controlPlanes = storageBackend;
      certType = authTypes.pinned;
    };
    sysAccount = filterSystemAccountTokenPlanes storageBackend;
  };

  # Create all filtered collections for control planes using tagged approach (O(1) lookups)
  createFilteredControlPlaneCollections =
    taggedValidatedControlPlanes:
    let
      # O(1) tag-based filters - no more iterations!
      pkiCertControlPlanes = filterByTag "pkiAndCert" taggedValidatedControlPlanes;
      pinnedCertControlPlanes = filterByTag "pinnedAndCert" taggedValidatedControlPlanes;

      # Storage-based filters (still O(1) lookups)
      hcvStorageControlPlanes = filterByStorageTag {
        taggedControlPlanes = taggedValidatedControlPlanes;
        backend = "hcv";
      };
      awsStorageControlPlanes = filterByStorageTag {
        taggedControlPlanes = taggedValidatedControlPlanes;
        backend = "aws";
        requireEnabled = true;
      };
      localStorageControlPlanes = filterByStorageTag {
        taggedControlPlanes = taggedValidatedControlPlanes;
        backend = "local";
      };

      # Individual system account filters
      individualSystemAccountPlanes = filterByTag "systemAccountEnabled" taggedValidatedControlPlanes;

      # Other O(1) filters
      outputEnabledControlPlanes = filterAttrs (_: cp: cp.output or false) taggedValidatedControlPlanes;
      storageRequiredControlPlanes = filterByTag "needsStorage" taggedValidatedControlPlanes;

      # AWS-specific filters (still O(1))
      awsProviderRequiredControlPlanes = filterAttrs (
        _: cp: cp._tags.usesAws || cp._tags.awsEnabled
      ) taggedValidatedControlPlanes;
      awsEnabledControlPlanes = filterByTag "awsEnabled" taggedValidatedControlPlanes;
      awsEnabledWithStorage = filterByTag "awsStorageEnabled" taggedValidatedControlPlanes;

      # Combined storage + cert type filters (still O(1) - just chaining O(1) operations)
      awsStoragePkiCertControlPlanes = filterByTag "pkiAndCert" awsStorageControlPlanes;
      awsStoragePinnedCertControlPlanes = filterByTag "pinnedAndCert" awsStorageControlPlanes;
      awsStorageSysAccountControlPlanes = filterByTag "systemAccountWithToken" awsStorageControlPlanes;

      hcvStoragePkiCertControlPlanes = filterByTag "pkiAndCert" hcvStorageControlPlanes;
      hcvStoragePinnedCertControlPlanes = filterByTag "pinnedAndCert" hcvStorageControlPlanes;
      hcvStorageSysAccountControlPlanes = filterByTag "systemAccountWithToken" hcvStorageControlPlanes;

      localStoragePkiCertControlPlanes = filterByTag "pkiAndCert" localStorageControlPlanes;
      localStoragePinnedCertControlPlanes = filterByTag "pinnedAndCert" localStorageControlPlanes;
      localStorageSysAccountControlPlanes = filterByTag "systemAccountWithToken" localStorageControlPlanes;
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
        awsProviderRequiredControlPlanes
        awsEnabledControlPlanes
        awsEnabledWithStorage
        awsStoragePkiCertControlPlanes
        awsStoragePinnedCertControlPlanes
        awsStorageSysAccountControlPlanes
        hcvStoragePkiCertControlPlanes
        hcvStoragePinnedCertControlPlanes
        hcvStorageSysAccountControlPlanes
        localStoragePkiCertControlPlanes
        localStoragePinnedCertControlPlanes
        localStorageSysAccountControlPlanes
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
      throw "Control plane group '${firstError.name}' cannot reference other control plane groups: ${membersList}. Groups may only reference individual control planes."
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

      # Validation 3: Members of control plane groups must not have create_certificates = true
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
      throw "Control plane '${name}' has members ${toString cp.members} but cluster_type is not CLUSTER_TYPE_CONTROL_PLANE_GROUP"
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

      # Apply validation if requested (simple group validation first!)
      validatedControlPlanes =
        if validation then
          let
            # First, validate that groups don't reference other groups
            planesWithoutGroupReferences = validateNoGroupReferences controlPlanesWithLabels;

            # Then apply individual control plane validation
            individuallyValidated = mapAttrs (
              name: cp:
              validateControlPlane {
                inherit name cp defaults;
                allControlPlanes = planesWithoutGroupReferences; # Fixed: Pass full attrset
              }
            ) planesWithoutGroupReferences;
          in
          individuallyValidated
        else
          controlPlanesWithLabels;

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
      # Process control planes once with tagging
      processed = processControlPlanes { inherit cps defaultLabels defaults; };

      # Process groups once
      groupProcessed = processGroups { inherit groups; };
    in
    processed
    // createFilteredControlPlaneCollections processed.taggedValidatedControlPlanes
    // {
      # Group-specific fields (computed only when accessed)
      storageRequiredGroups = filter (group: group.groupConfig.generate_token) groupProcessed.validatedGroups;
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

      # Generic group filter (similar to makeStorageFilter but for groups)
      groupStorageFilter =
        group:
        elem backend group.groupConfig.storage_backend
        && group.groupConfig.generate_token
        && (if backend == "aws" then (group.groupConfig.aws.enable or false) else true);
    in
    if !validBackend then
      throw "Invalid storage backend '${backend}'. Supported backends: ${concatStringsSep ", " validBackends}"
    else
      filter groupStorageFilter flattened;

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
