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
    #
    # NVFlare-specific metadata
    #
    job_uuid                           = "${JOB_UUID}"
    hostname                           = "${meta.domain}-${BASE_DOMAIN}"
    force_pull_images                  = false
    #
    # dashboard
    #
    image_dashboard                    = "registry.services.ai4os.eu/ai4os/ai4os-nvflare-dashboard"
    dashboard_credentials              = "${NVFLARE_DASHBOARD_USERNAME}:${NVFLARE_DASHBOARD_PASSWORD}"
    #
    # server
    #
    image_server                       = "registry.services.ai4os.eu/ai4os/ai4os-nvflare-server"
    RCLONE_CONFIG                      = "${RCLONE_CONFIG}"
    RCLONE_CONFIG_RSHARE_TYPE          = "webdav"
    RCLONE_CONFIG_RSHARE_URL           = "${RCLONE_CONFIG_RSHARE_URL}"
    RCLONE_CONFIG_RSHARE_VENDOR        = "${RCLONE_CONFIG_RSHARE_VENDOR}"
    RCLONE_CONFIG_RSHARE_USER          = "${RCLONE_CONFIG_RSHARE_USER}"
    RCLONE_CONFIG_RSHARE_PASS          = "${RCLONE_CONFIG_RSHARE_PASS}"
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
      port "dashboard-api" {
        to = 8443
      }
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
        "traefik.http.routers.${JOB_UUID}-dashboard.rule=Host(`dashboard-${HOSTNAME}.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }
 
    service {
      name = "${JOB_UUID}-dashboard-api"
      port = "dashboard-api"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${JOB_UUID}-dashboard-api.tls=true",
        "traefik.http.routers.${JOB_UUID}-dashboard-api.entrypoints=websecure",
        "traefik.http.routers.${JOB_UUID}-dashboard-api.rule=Host(`dashboard-api-${HOSTNAME}.${meta.domain}-${BASE_DOMAIN}`)",
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
        "traefik.tcp.routers.${JOB_UUID}-server-fl.rule=HostSNI(`server-${HOSTNAME}.${meta.domain}-${BASE_DOMAIN}`)",
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
        "traefik.tcp.routers.${JOB_UUID}-server-admin.rule=HostSNI(`server-${HOSTNAME}.${meta.domain}-${BASE_DOMAIN}`)",
      ]
    }
 
    service {
      name = "${JOB_UUID}-server-jupyter"
      port = "server-jupyter"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.tls=true",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.entrypoints=websecure",
        "traefik.http.routers.${JOB_UUID}-server-jupyter.rule=Host(`server-${HOSTNAME}.${meta.domain}-${BASE_DOMAIN}`)",
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
        REMOTE_PATH                 = "rshare:/nvflare-instances/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}"
        LOCAL_PATH                  = "/storage"
      }
      config {
        image   = "ignacioheredia/ai4-docker-storage"
        privileged = true
        volumes = [
          "/nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}:/storage:shared",
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
     
    task "storagecleanup" {
      lifecycle {
        hook = "poststop"
      }
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args = [
          "-c",
          "sudo umount /nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN} && sudo rmdir /nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}"
        ]
      }
    }
     
    task "dashboard" {
      driver = "docker"
      env {
        NVFL_CREDENTIAL = "${NOMAD_META_dashboard_credentials}"
        VARIABLE_NAME = "app"
      }
      config {
        image = "${NOMAD_META_image_dashboard}"
        force_pull = "${NOMAD_META_force_pull_images}"
        ports = ["dashboard", "dashboard-api"]
        volumes = [
          "/nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}/dashboard:/var/tmp/nvflare/dashboard:shared",
        ]
      }
    }
 
    task "server" {
      driver = "docker"
      config {
        image = "${NOMAD_META_image_server}"
        force_pull = "${NOMAD_META_force_pull_images}"
        ports = ["server-fl", "server-admin", "server-jupyter"]
        volumes = [
          "/nomad-storage/${JOB_UUID}.${meta.domain}-${BASE_DOMAIN}/server/tf:/tf:shared",
        ]
        command = "jupyter-lab"
        args = [
          # passwd: server
          # how to generate password: python3 -c "from jupyter_server.auth import passwd; print(passwd('server'))"
          "--ServerApp.password='${NVFLARE_SERVER_JUPYTER_PASSWORD}'",
          "--port=8888",
          "--ip=0.0.0.0",
          "--notebook-dir=/tf",
          "--no-browser",
          "--allow-root"
        ]
      }
    }
     
  }
}

