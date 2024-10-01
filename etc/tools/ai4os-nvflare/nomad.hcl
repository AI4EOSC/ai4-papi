/*
Convention:
-----------
* ${UPPERCASE} are replaced by the user
* ${lowercase} are replace by Nomad at launchtime
* remaining is default, same for everybody

When replacing user values we use safe_substitute() so that ge don't get an error for not
replacing Nomad values
*/

job "tool-nvflare-${JOB_UUID}" {
  namespace = "${NAMESPACE}"
  type      = "service"
  region    = "global"
  id        = "${JOB_UUID}"
  priority  = "${PRIORITY}"
   
  meta {
    owner                             = "${OWNER}"  # user-id from OIDC
    owner_name                        = "${OWNER_NAME}"
    owner_email                       = "${OWNER_EMAIL}"
    title                             = "${TITLE}"
    description                       = "${DESCRIPTION}"
    job_uuid                          = "${JOB_UUID}"
    hostname                          = "${meta.domain}-${BASE_DOMAIN}"
    force_pull_images                 = true
    #
    # NVFLARE Dashboard
    #
    image_dashboard                    = "registry.services.ai4os.eu/ai4os/ai4os-nvflare-dashboard"
    #
    # NVFLARE Server
    #
    image_server                       = "registry.services.ai4os.eu/ai4os/ai4os-nvflare-server"
    RCLONE_CONFIG                      = "${RCLONE_CONFIG}"
    RCLONE_CONFIG_RSHARE_TYPE          = "webdav"
    RCLONE_CONFIG_RSHARE_URL           = "${RCLONE_CONFIG_RSHARE_URL}"
    RCLONE_CONFIG_RSHARE_VENDOR        = "${RCLONE_CONFIG_RSHARE_VENDOR}"
    RCLONE_CONFIG_RSHARE_USER          = "${RCLONE_CONFIG_RSHARE_USER}"
    RCLONE_CONFIG_RSHARE_PASS          = "${RCLONE_CONFIG_RSHARE_PASS}"
    RCLONE_REMOTE_PATH                 = "${RCLONE_REMOTE_PATH}"
  }

  # Only use nodes that have succesfully passed the ai4-nomad_tests (ie. meta.status=ready)
  constraint {
    attribute = "${meta.status}"
    operator  = "regexp"
    value     = "ready"
  }

  # Only launch in compute nodes (to avoid clashing with system jobs, eg. Traefik)
  constraint {
    attribute = "${meta.compute}"
    operator  = "="
    value     = "true"
  }

  # Only deploy in nodes serving that namespace (we use metadata instead of node-pools
  # because Nomad does not allow a node to belong to several node pools)
  constraint {
    attribute = "${meta.namespace}"
    operator  = "regexp"
    value     = "${NAMESPACE}"
  }

  # Try to deploy iMagine jobs on nodes that are iMagine-exclusive
  # In this way, we leave AI4EOSC nodes for AI4EOSC users and for iMagine users only
  # when iMagine nodes are fully booked.
  affinity {
    attribute = "${meta.namespace}"
    operator  = "regexp"
    value     = "ai4eosc"
    weight    = -50  # anti-affinity for ai4eosc clients
  }

  # CPU-only jobs should deploy *preferably* on CPU clients (affinity) to avoid
  # overloading GPU clients with CPU-only jobs.
  affinity {
    attribute = "${meta.tags}"
    operator  = "regexp"
    value     = "cpu"
    weight    = 50
  }

  # Avoid rescheduling the job on **other** nodes during a network cut
  # Command not working due to https://github.com/hashicorp/nomad/issues/16515
  reschedule {
    attempts  = 0
    unlimited = false
  }
 
  group "usergroup" {
 
    network {
      port "dashboard" {
        to = 80
      }
      port "server-fl" {
        to = 8002
      }
      port "server-admin" {
        to = 8003
      }
      port "server-jupyter" {
        to = 8888
      }
    }
     
    service {
      name = "${JOB_UUID}-dashboard"
      port = "dashboard"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${JOB_UUID}-dashboard.tls=true",
        "traefik.http.routers.${JOB_UUID}-dashboard.entrypoints=websecure",
        "traefik.http.routers.${JOB_UUID}-dashboard.rule=Host(`${JOB_UUID}-dashboard.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }

    service {
      name = "${JOB_UUID}-server-fl"
      port = "server-fl"
      tags = [
        "traefik.enable=true",
        "traefik.tcp.routers.${JOB_UUID}-server-fl.tls=true",
        "traefik.tcp.routers.${JOB_UUID}-server-fl.tls.passthrough=true",
        "traefik.tcp.routers.${JOB_UUID}-server-fl.entrypoints=nvflare_fl",
        "traefik.tcp.routers.${JOB_UUID}-server-fl.rule=HostSNI(`${JOB_UUID}-server.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }
 
    service {
      name = "${JOB_UUID}-server-admin"
      port = "server-admin"
      tags = [
        "traefik.enable=true",
        "traefik.tcp.routers.${JOB_UUID}-server-admin.tls=true",
        "traefik.tcp.routers.${JOB_UUID}-server-admin.tls.passthrough=true",
        "traefik.tcp.routers.${JOB_UUID}-server-admin.entrypoints=nvflare_admin",
        "traefik.tcp.routers.${JOB_UUID}-server-admin.rule=HostSNI(`${JOB_UUID}-server.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }
 
    service {
      name = "${JOB_UUID}-server-jupyter"
      port = "server-jupyter"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.tls=true",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.entrypoints=websecure",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.rule=Host(`${JOB_UUID}-server.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }

    ephemeral_disk {
      size = ${DISK}
    }
 
    task "storagetask" {
      lifecycle {
        hook = "prestart"
        sidecar = "true"
      }
      driver = "docker"
      env {
        RCLONE_CONFIG               = "${NOMAD_META_RCLONE_CONFIG}"
        RCLONE_CONFIG_RSHARE_TYPE   = "webdav"
        RCLONE_CONFIG_RSHARE_URL    = "${NOMAD_META_RCLONE_CONFIG_RSHARE_URL}"
        RCLONE_CONFIG_RSHARE_VENDOR = "${NOMAD_META_RCLONE_CONFIG_RSHARE_VENDOR}"
        RCLONE_CONFIG_RSHARE_USER   = "${NOMAD_META_RCLONE_CONFIG_RSHARE_USER}"
        RCLONE_CONFIG_RSHARE_PASS   = "${NOMAD_META_RCLONE_CONFIG_RSHARE_PASS}"
        REMOTE_PATH                 = "rshare:${NOMAD_META_RCLONE_REMOTE_PATH}"
        LOCAL_PATH                  = "/storage"
      }
      config {
        force_pull  = true
        image       = "registry.services.ai4os.eu/ai4os/docker-storage:latest"
        privileged  = true
        volumes = [
          "..${NOMAD_ALLOC_DIR}/data/storage:/storage:rshared"
        ]
        mount {
          type = "bind"
          target = "/srv/.rclone/rclone.conf"
          source = "local/rclone.conf"
          readonly = false
        }
        mount {
          type = "bind"
          target = "/mount_storage.sh"
          source = "local/mount_storage.sh"
          readonly = false
        }
      }
      template {
        data = <<-EOF
        [ai4eosc-share]
        type = webdav
        url = https://share.services.ai4os.eu/remote.php/dav
        vendor = nextcloud
        user = ${NOMAD_META_RCLONE_CONFIG_RSHARE_USER}
        pass = ${NOMAD_META_RCLONE_CONFIG_RSHARE_PASS}
        EOF
        destination = "local/rclone.conf"
      }
      template {
        data = <<-EOF
        export RCLONE_CONFIG_RSHARE_PASS=$(rclone obscure $RCLONE_CONFIG_RSHARE_PASS)
        rclone mount $REMOTE_PATH $LOCAL_PATH --allow-non-empty --allow-other --vfs-cache-mode full
        EOF
        destination = "local/mount_storage.sh"
      }
      resources {
        cpu    = 50        # minimum number of CPU MHz is 2
        memory = 2000
      }
    }
     
    task "dashboard" {
      driver = "docker"
      env {
        NVFL_CREDENTIAL="${NVFL_DASHBOARD_USERNAME}:${NVFL_DASHBOARD_PASSWORD}"
        NVFL_SERVER1="${NVFL_DASHBOARD_SERVER_SERVER1}"
        NVFL_SERVER2="${NVFL_DASHBOARD_SERVER_SERVER2}"
        NVFL_PROJECT_SHORT_NAME="${NVFL_DASHBOARD_PROJECT_SHORT_NAME}"
        NVFL_PROJECT_TITLE="${NVFL_DASHBOARD_PROJECT_TITLE}"
        NVFL_PROJECT_DESCRIPTION="${NVFL_DASHBOARD_PROJECT_DESCRIPTION}"
        NVFL_PROJECT_APP_LOCATION="${NVFL_DASHBOARD_PROJECT_APP_LOCATION}"
        NVFL_PROJECT_STARTING_DATE="${NVFL_DASHBOARD_PROJECT_STARTING_DATE}"
        NVFL_PROJECT_END_DATE="${NVFL_DASHBOARD_PROJECT_END_DATE}"
        NVFL_PROJECT_PUBLIC=${NVFL_DASHBOARD_PROJECT_PUBLIC}
        NVFL_PROJECT_FROZEN=${NVFL_DASHBOARD_PROJECT_FROZEN}
        VARIABLE_NAME="app"
      }
      config {
        image = "${NOMAD_META_image_dashboard}:${NVFL_VERSION}"
        force_pull = "${NOMAD_META_force_pull_images}"
        ports = ["dashboard"]
        volumes = [
          "/nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}/dashboard:/var/tmp/nvflare/dashboard:shared",
        ]
      }
    }
 
    task "server" {
      driver = "docker"
      config {
        image = "${NOMAD_META_image_server}:${NVFL_VERSION}"
        force_pull = "${NOMAD_META_force_pull_images}"
        ports = ["server-fl", "server-admin", "server-jupyter"]
        shm_size = ${SHARED_MEMORY}
        memory_hard_limit = ${RAM}
        storage_opt = {
          size = "${DISK}M"
        }
        volumes = [
          "/nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}/server/tf:/tf:shared",
        ]
        command = "jupyter-lab"
        args = [
          # passwd: server
          # how to generate password: python3 -c "from jupyter_server.auth import passwd; print(passwd('server'))"
          "--ServerApp.password='${NVFL_SERVER_JUPYTER_PASSWORD}'",
          "--port=8888",
          "--ip=0.0.0.0",
          "--notebook-dir=/tf",
          "--no-browser",
          "--allow-root"
        ]
      }

      resources {
        cores  = ${CPU_NUM}
        memory = ${RAM}
        memory_max = ${RAM}
      }
    }
     
  }
}

