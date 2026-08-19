require "test_helper"

class TrinoK8sClientTest < ActiveSupport::TestCase
  class FakeKubeClient
    attr_reader :patches

    def initialize(ready_replicas: 1, replicas: 1)
      @ready_replicas = ready_replicas
      @replicas = replicas
      @patches = []
    end

    def json_patch_deployment(name, patch, namespace)
      @patches << { name: name, namespace: namespace, patch: patch }
    end

    def get_deployment(name, namespace)
      OpenStruct.new(status: { "readyReplicas" => @ready_replicas },
                     spec: { "replicas" => @replicas })
    end
  end

  test "scales the deployment up and down through the patch call" do
    kube = FakeKubeClient.new
    client = TrinoK8sClient.new(client: K8sClient.new(kube, namespace: "trino", deployment: "trino-coordinator"))

    client.scale(1)
    client.scale(0)

    assert_equal [ 1, 0 ], kube.patches.map { |p| p[:patch].first[:value] }
  end

  test "reports readiness from readyReplicas" do
    ready = TrinoK8sClient.new(client: K8sClient.new(FakeKubeClient.new(ready_replicas: 1),
                                                     namespace: "trino", deployment: "trino"))
    not_ready = TrinoK8sClient.new(client: K8sClient.new(FakeKubeClient.new(ready_replicas: 0),
                                                         namespace: "trino", deployment: "trino"))

    assert ready.ready?
    assert_not not_ready.ready?
  end

  test "reports the desired replica count" do
    client = TrinoK8sClient.new(client: K8sClient.new(FakeKubeClient.new(replicas: 2),
                                                      namespace: "trino", deployment: "trino"))

    assert_equal 2, client.replicas
  end
end
