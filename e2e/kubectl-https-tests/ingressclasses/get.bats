#!/usr/bin/env bats

load "$BATS_TEST_DIRNAME/../../libs/tenants_utils.bash"
load "$BATS_TEST_DIRNAME/../../libs/poll.bash"
load "$BATS_TEST_DIRNAME/../../libs/namespaces_utils.bash"
load "$BATS_TEST_DIRNAME/../../libs/ingressclass_utils.bash"
load "$BATS_TEST_DIRNAME/../../libs/serviceaccount_utils.bash"

setup() {
  create_tenant ingressclassuser alice User
  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/ingressOptions", "value": {"allowedClasses": {"allowed": ["custom"], "allowedRegex": "\\w+-lb"}}}]'
  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/owners/1", "value": {"kind": "ServiceAccount", "name": "system:serviceaccount:ingressclassuser-namespace:sa"}}]'
  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/owners/2", "value": {"kind": "Group", "name": "foo.clastix.io"}}]'
  create_namespace alice ingressclassuser-namespace
  create_serviceaccount sa ingressclassuser-namespace

  create_tenant ingressclassgroup foo.clastix.io Group
  kubectl patch tenants.capsule.clastix.io ingressclassgroup --type=json -p '[{"op": "add", "path": "/spec/ingressOptions", "value": {"allowedClasses": {"allowed": ["custom2"]}}}]'

  if [[ $(kubectl version -o json | jq -r .serverVersion.minor) -gt 17 ]]; then
    local version="v1"
    if [[ $(kubectl version -o json | jq -r .serverVersion.minor) -lt 19 ]]; then
      version="v1beta1"
    fi
    create_ingressclass "${version}" custom
    create_ingressclass "${version}" custom2
    create_ingressclass "${version}" external-lb
    create_ingressclass "${version}" internal-lb
    create_ingressclass "${version}" nonallowed
  fi
}

teardown() {
  delete_tenant ingressclassuser
  delete_tenant ingressclassgroup

  delete_ingressclass custom || true
  delete_ingressclass custom2 || true
  delete_ingressclass external-lb || true
  delete_ingressclass internal-lb || true
  delete_ingressclass nonallowed || true
}

@test "Get ingressClass without permissions" {
  if [[ $(kubectl version -o json | jq -r .serverVersion.minor) -lt 18 ]]; then
    kubectl version
    skip "IngressClass resources is not supported on Kubernetes < 1.18"
  fi

  poll_until_equals "User" "" "kubectl --kubeconfig=${HACK_DIR}/alice.kubeconfig get ingressclasses.networking.k8s.io custom --output=name" 3 5
  poll_until_equals "SA" "" "kubectl --kubeconfig=${HACK_DIR}/sa.kubeconfig get ingressclasses.networking.k8s.io custom --output=name" 3 5
  poll_until_equals "Group" "" "kubectl --kubeconfig=${HACK_DIR}/foo.clastix.io.kubeconfig  get ingressclasses.networking.k8s.io custom --output=name" 3 5
}

@test "Get ingressClass with List operation" {
  if [[ $(kubectl version -o json | jq -r .serverVersion.minor) -lt 18 ]]; then
    kubectl version
    skip "IngressClass resources is not supported on Kubernetes < 1.18"
  fi

  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/owners/0/proxySettings","value":[{"kind": "IngressClasses", "operations": ["List"]}]}]'
  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/owners/1/proxySettings","value":[{"kind": "IngressClasses", "operations": ["List"]}]}]'
  kubectl patch tenants.capsule.clastix.io ingressclassuser --type=json -p '[{"op": "add", "path": "/spec/owners/2/proxySettings","value":[{"kind": "IngressClasses", "operations": ["List"]}]}]'
  kubectl patch tenants.capsule.clastix.io ingressclassgroup --type=json -p '[{"op": "add", "path": "/spec/owners/0/proxySettings","value":[{"kind": "IngressClasses", "operations": ["List"]}]}]'

  echo "Get allowed ingressClass" >&3
  local list="ingressclass.networking.k8s.io/custom"
  poll_until_equals "User" "$list" "kubectl --kubeconfig=${HACK_DIR}/alice.kubeconfig get ingressclasses.networking.k8s.io custom --output=name" 3 5
  poll_until_equals "SA" "$list" "kubectl --kubeconfig=${HACK_DIR}/sa.kubeconfig get ingressclasses.networking.k8s.io custom --output=name" 3 5
  poll_until_equals "Group - storageClass 1" "ingressclass.networking.k8s.io/custom2" "kubectl --kubeconfig=${HACK_DIR}/foo.clastix.io.kubeconfig get ingressclasses.networking.k8s.io custom2 --output=name" 3 5
  poll_until_equals "Group - storageClass 2" "$list" "kubectl --kubeconfig=${HACK_DIR}/foo.clastix.io.kubeconfig get ingressclasses.networking.k8s.io custom --output=name" 3 5

  echo "Get nonallowed ingressClass" >&3
  run kubectl --kubeconfig=${HACK_DIR}/alice.kubeconfig get ingressclasses.networking.k8s.io nonallowed --output=name
  [ $status -eq 1 ]
  [ "${lines[0]}" = 'Error from server (NotFound): ingressclasses.networking.k8s.io "nonallowed" not found' ]

  run kubectl --kubeconfig=${HACK_DIR}/sa.kubeconfig get ingressclasses.networking.k8s.io nonallowed --output=name
  [ $status -eq 1 ]
  [ "${lines[0]}" = 'Error from server (NotFound): ingressclasses.networking.k8s.io "nonallowed" not found' ]

  run kubectl --kubeconfig=${HACK_DIR}/foo.clastix.io.kubeconfig get ingressclasses.networking.k8s.io nonallowed --output=name
  [ $status -eq 1 ]
  [ "${lines[0]}" = 'Error from server (NotFound): ingressclasses.networking.k8s.io "nonallowed" not found' ]
}
