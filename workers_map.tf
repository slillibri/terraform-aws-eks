terraform {
  # Optional attributes and the defaults function are
  # both experimental, so we must opt in to the experiment.
  experiments = [module_variable_optional_attrs]
}

/*
Why does this exist?
This piece of terraform is a stop-gap until the great 18.x refactor is complete in the
upstream terraform-aws-eks module is complete. We may/may not need to modify our list of
node pools, and in the current case, this is a very disruptive change. This is a bit of
side-loaded code to allow us to move forward without waiting for the upstream. It shouldn't
conflict or change anything about the upstream, so we should be able to continue using the
upstream with minimal changes.
*/

/*
So, this is horrible because all the objects in a map must have the same type, but we have
node-pools that do and don't have override_instance_types, we have node-pools that do and
don't have iam_role_id, etc. I am enabling optional vars in this current workaround until
the great 18.x refactor of the upstream is complete.
*/
variable "workers_map" {
  type = map(object({
    name                    = string,
    kubelet_extra_args      = optional(string),
    instance_type           = optional(string),
    override_instance_types = optional(list(string)),
    tags                    = optional(list(object({
      key = optional(string),
      value = optional(string),
      propagate_at_launch = optional(bool),
      }))),
    asg_desired_capacity    = optional(number),
    asg_max_size            = optional(number),
    asg_min_size            = optional(number),
    iam_role_id             = optional(string),
    subnets                 = optional(list(string)),
  }))
  description = "This is a map representation of the worker_groups_launch_template from the original upstream module"
  default = {
  }
}

locals {
  workers_map_userdata_rendered = {
    for k, v in var.workers_map : k => templatefile(
      lookup(
        v,
        "userdata_template_file",
        lookup(v, "platform", local.workers_group_defaults["platform"]) == "windows"
        ? "${path.module}/templates/userdata_windows.tpl"
        : "${path.module}/templates/userdata.sh.tpl"
      ),
      merge({
        platform            = lookup(v, "platform", local.workers_group_defaults["platform"])
        cluster_name        = local.cluster_name
        endpoint            = local.cluster_endpoint
        cluster_auth_base64 = local.cluster_auth_base64
        pre_userdata = lookup(
          v,
          "pre_userdata",
          local.workers_group_defaults["pre_userdata"],
        )
        additional_userdata = lookup(
          v,
          "additional_userdata",
          local.workers_group_defaults["additional_userdata"],
        )
        bootstrap_extra_args = lookup(
          v,
          "bootstrap_extra_args",
          local.workers_group_defaults["bootstrap_extra_args"],
        )
        kubelet_extra_args = lookup(
          v,
          "kubelet_extra_args",
          local.workers_group_defaults["kubelet_extra_args"],
        )
        },
        lookup(
          v,
          "userdata_template_extra_args",
          local.workers_group_defaults["userdata_template_extra_args"]
        )
      )
    )
  }
}
# Worker Groups using Launch Templates

data "aws_iam_instance_profile" "custom_workers_map_iam_instance_profile" {
  //count = var.manage_worker_iam_resources ? 0 : local.worker_group_launch_template_count
  for_each = var.manage_worker_iam_resources ? {} : tomap(var.workers_map)

  name = lookup(
    each.value,
    "iam_instance_profile_name",
    local.workers_group_defaults["iam_instance_profile_name"],
  )
}

resource "aws_autoscaling_group" "workers_map" {
  //count = var.create_eks ? local.worker_group_launch_template_count : 0
  for_each = tomap(var.workers_map)

  name_prefix = join(
    "-",
    compact(
      [
        local.cluster_name,
        lookup(each.value, "name")
      ]
    )
  )
  desired_capacity = lookup(
    each.value,
    "asg_desired_capacity",
    local.workers_group_defaults["asg_desired_capacity"],
  )
  max_size = lookup(
    each.value,
    "asg_max_size",
    local.workers_group_defaults["asg_max_size"],
  )
  min_size = lookup(
    each.value,
    "asg_min_size",
    local.workers_group_defaults["asg_min_size"],
  )
  force_delete = lookup(
    each.value,
    "asg_force_delete",
    local.workers_group_defaults["asg_force_delete"],
  )
  target_group_arns = lookup(
    each.value,
    "target_group_arns",
    local.workers_group_defaults["target_group_arns"]
  )
  load_balancers = lookup(
    each.value,
    "load_balancers",
    local.workers_group_defaults["load_balancers"]
  )
  service_linked_role_arn = lookup(
    each.value,
    "service_linked_role_arn",
    local.workers_group_defaults["service_linked_role_arn"],
  )
  vpc_zone_identifier = lookup(
    each.value,
    "subnets",
    local.workers_group_defaults["subnets"]
  )
  protect_from_scale_in = lookup(
    each.value,
    "protect_from_scale_in",
    local.workers_group_defaults["protect_from_scale_in"],
  )
  suspended_processes = lookup(
    each.value,
    "suspended_processes",
    local.workers_group_defaults["suspended_processes"]
  )
  enabled_metrics = lookup(
    each.value,
    "enabled_metrics",
    local.workers_group_defaults["enabled_metrics"]
  )
  placement_group = lookup(
    each.value,
    "placement_group",
    local.workers_group_defaults["placement_group"],
  )
  termination_policies = lookup(
    each.value,
    "termination_policies",
    local.workers_group_defaults["termination_policies"]
  )
  max_instance_lifetime = lookup(
    each.value,
    "max_instance_lifetime",
    local.workers_group_defaults["max_instance_lifetime"],
  )
  default_cooldown = lookup(
    each.value,
    "default_cooldown",
    local.workers_group_defaults["default_cooldown"]
  )
  health_check_type = lookup(
    each.value,
    "health_check_type",
    local.workers_group_defaults["health_check_type"]
  )
  health_check_grace_period = lookup(
    each.value,
    "health_check_grace_period",
    local.workers_group_defaults["health_check_grace_period"]
  )
  capacity_rebalance = lookup(
    each.value,
    "capacity_rebalance",
    local.workers_group_defaults["capacity_rebalance"]
  )

  dynamic "mixed_instances_policy" {
    iterator = item
    for_each = (lookup(each.value, "override_instance_types", null) != null) || (lookup(each.value, "on_demand_allocation_strategy", local.workers_group_defaults["on_demand_allocation_strategy"]) != null) ? [each.value] : []

    content {
      instances_distribution {
        on_demand_allocation_strategy = lookup(
          item.value,
          "on_demand_allocation_strategy",
          "prioritized",
        )
        on_demand_base_capacity = lookup(
          item.value,
          "on_demand_base_capacity",
          local.workers_group_defaults["on_demand_base_capacity"],
        )
        on_demand_percentage_above_base_capacity = lookup(
          item.value,
          "on_demand_percentage_above_base_capacity",
          local.workers_group_defaults["on_demand_percentage_above_base_capacity"],
        )
        spot_allocation_strategy = lookup(
          item.value,
          "spot_allocation_strategy",
          local.workers_group_defaults["spot_allocation_strategy"],
        )
        spot_instance_pools = lookup(
          item.value,
          "spot_instance_pools",
          local.workers_group_defaults["spot_instance_pools"],
        )
        spot_max_price = lookup(
          item.value,
          "spot_max_price",
          local.workers_group_defaults["spot_max_price"],
        )
      }

      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.workers_map[each.value["name"]].id
          version = lookup(
            each.value,
            "launch_template_version",
            lookup(
              each.value,
              "launch_template_version",
              local.workers_group_defaults["launch_template_version"]
            ) == "$Latest"
            ? aws_launch_template.workers_map[each.value["name"]].latest_version
            : aws_launch_template.workers_map[each.value["name"]].default_version
          )
        }

        dynamic "override" {
          for_each = lookup(
            each.value,
            "override_instance_types",
            local.workers_group_defaults["override_instance_types"]
          )

          content {
            instance_type = override.value
          }
        }
      }
    }
  }

  dynamic "launch_template" {
    iterator = item
    for_each = (lookup(each.value, "override_instance_types", null) != null) || (lookup(each.value, "on_demand_allocation_strategy", local.workers_group_defaults["on_demand_allocation_strategy"]) != null) ? [] : [each.value]

    content {
      id = aws_launch_template.workers_map[each.value["name"]].id
      version = lookup(
        each.value,
        "launch_template_version",
        lookup(
          each.value,
          "launch_template_version",
          local.workers_group_defaults["launch_template_version"]
        ) == "$Latest"
        ? aws_launch_template.workers_map[each.value["name"]].latest_version
        : aws_launch_template.workers_map[each.value["name"]].default_version
      )
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = var.worker_create_initial_lifecycle_hooks ? lookup(each.value, "asg_initial_lifecycle_hooks", local.workers_group_defaults["asg_initial_lifecycle_hooks"]) : []
    content {
      name                    = initial_lifecycle_hook.value["name"]
      lifecycle_transition    = initial_lifecycle_hook.value["lifecycle_transition"]
      notification_metadata   = lookup(initial_lifecycle_hook.value, "notification_metadata", null)
      heartbeat_timeout       = lookup(initial_lifecycle_hook.value, "heartbeat_timeout", null)
      notification_target_arn = lookup(initial_lifecycle_hook.value, "notification_target_arn", null)
      role_arn                = lookup(initial_lifecycle_hook.value, "role_arn", null)
      default_result          = lookup(initial_lifecycle_hook.value, "default_result", null)
    }
  }

  dynamic "warm_pool" {
    for_each = lookup(each.value, "warm_pool", null) != null ? [lookup(each.value, "warm_pool")] : []

    content {
      pool_state                  = lookup(warm_pool.value, "pool_state", null)
      min_size                    = lookup(warm_pool.value, "min_size", null)
      max_group_prepared_capacity = lookup(warm_pool.value, "max_group_prepared_capacity", null)
    }
  }

  dynamic "tag" {
    for_each = concat(
      [
        {
          "key" = "Name"
          "value" = "${local.cluster_name}-${lookup(
            each.value,
            "name",
            ""
          )}-eks_asg"
          "propagate_at_launch" = true
        },
        {
          "key"                 = "kubernetes.io/cluster/${local.cluster_name}"
          "value"               = "owned"
          "propagate_at_launch" = true
        },
      ],
      [
        for tag_key, tag_value in var.tags :
        tomap({
          key                 = tag_key
          value               = tag_value
          propagate_at_launch = "true"
        })
        if tag_key != "Name" && !contains([for tag in lookup(each.value, "tags", local.workers_group_defaults["tags"]) : tag["key"]], tag_key)
      ],
      lookup(
        each.value,
        "tags",
        local.workers_group_defaults["tags"]
      )
    )
    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = tag.value.propagate_at_launch
    }
  }

  # logic duplicated in workers.tf
  dynamic "instance_refresh" {
    for_each = lookup(each.value,
      "instance_refresh_enabled",
    local.workers_group_defaults["instance_refresh_enabled"]) ? [1] : []
    content {
      strategy = lookup(
        each.value, "instance_refresh_strategy",
        local.workers_group_defaults["instance_refresh_strategy"]
      )
      preferences {
        instance_warmup = lookup(
          each.value, "instance_refresh_instance_warmup",
          local.workers_group_defaults["instance_refresh_instance_warmup"]
        )
        min_healthy_percentage = lookup(
          each.value, "instance_refresh_min_healthy_percentage",
          local.workers_group_defaults["instance_refresh_min_healthy_percentage"]
        )
      }
      triggers = lookup(
        each.value, "instance_refresh_triggers",
        local.workers_group_defaults["instance_refresh_triggers"]
      )
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

resource "aws_launch_template" "workers_map" {
  for_each = tomap(var.workers_map)

  name_prefix = "${local.cluster_name}-${lookup(
    each.value,
    "name",
    "",
  )}"

  update_default_version = lookup(
    each.value,
    "update_default_version",
    local.workers_group_defaults["update_default_version"],
  )

  network_interfaces {
    associate_public_ip_address = lookup(
      each.value,
      "public_ip",
      local.workers_group_defaults["public_ip"],
    )
    delete_on_termination = lookup(
      each.value,
      "eni_delete",
      local.workers_group_defaults["eni_delete"],
    )
    interface_type = lookup(
      each.value,
      "interface_type",
      local.workers_group_defaults["interface_type"],
    )
    security_groups = flatten([
      local.worker_security_group_id,
      var.worker_additional_security_group_ids,
      lookup(
        each.value,
        "additional_security_group_ids",
        local.workers_group_defaults["additional_security_group_ids"],
      ),
    ])
  }

//this might be more difficult?
  iam_instance_profile {
    name = try(aws_iam_instance_profile.workers_map[each.value["name"]].name, false) ? aws_iam_instance_profile.workers_map[each.value["name"]].name : data.aws_iam_instance_profile.custom_workers_map_iam_instance_profile[each.value["name"]].name
  }

  enclave_options {
    enabled = lookup(
      each.value,
      "enclave_support",
      local.workers_group_defaults["enclave_support"],
    )
  }

  image_id = lookup(
    each.value,
    "ami_id",
    lookup(each.value, "platform", local.workers_group_defaults["platform"]) == "windows" ? local.default_ami_id_windows : local.default_ami_id_linux,
  )
  instance_type = lookup(
    each.value,
    "instance_type",
    local.workers_group_defaults["instance_type"],
  )

  dynamic "elastic_inference_accelerator" {
    for_each = lookup(
      each.value,
      "elastic_inference_accelerator",
      local.workers_group_defaults["elastic_inference_accelerator"]
    ) != null ? [lookup(each.value, "elastic_inference_accelerator", local.workers_group_defaults["elastic_inference_accelerator"])] : []
    content {
      type = elastic_inference_accelerator.value
    }
  }

  key_name = lookup(
    each.value,
    "key_name",
    local.workers_group_defaults["key_name"],
  )
  user_data = base64encode(
    local.workers_map_userdata_rendered[each.value["name"]],
  )

  ebs_optimized = lookup(
    each.value,
    "ebs_optimized",
    !contains(
      local.ebs_optimized_not_supported,
      lookup(
        each.value,
        "instance_type",
        local.workers_group_defaults["instance_type"],
      )
    )
  )

  metadata_options {
    http_endpoint = lookup(
      each.value,
      "metadata_http_endpoint",
      local.workers_group_defaults["metadata_http_endpoint"],
    )
    http_tokens = lookup(
      each.value,
      "metadata_http_tokens",
      local.workers_group_defaults["metadata_http_tokens"],
    )
    http_put_response_hop_limit = lookup(
      each.value,
      "metadata_http_put_response_hop_limit",
      local.workers_group_defaults["metadata_http_put_response_hop_limit"],
    )
  }

  dynamic "credit_specification" {
    for_each = lookup(
      each.value,
      "cpu_credits",
      local.workers_group_defaults["cpu_credits"]
    ) != null ? [lookup(each.value, "cpu_credits", local.workers_group_defaults["cpu_credits"])] : []
    content {
      cpu_credits = credit_specification.value
    }
  }

  monitoring {
    enabled = lookup(
      each.value,
      "enable_monitoring",
      local.workers_group_defaults["enable_monitoring"],
    )
  }

  dynamic "placement" {
    for_each = lookup(each.value, "launch_template_placement_group", local.workers_group_defaults["launch_template_placement_group"]) != null ? [lookup(each.value, "launch_template_placement_group", local.workers_group_defaults["launch_template_placement_group"])] : []

    content {
      tenancy = lookup(
        each.value,
        "launch_template_placement_tenancy",
        local.workers_group_defaults["launch_template_placement_tenancy"],
      )
      group_name = placement.value
    }
  }

  dynamic "instance_market_options" {
    for_each = lookup(each.value, "market_type", null) == null ? [] : tolist([lookup(each.value, "market_type", null)])
    content {
      market_type = instance_market_options.value
    }
  }

  block_device_mappings {
    device_name = lookup(
      each.value,
      "root_block_device_name",
      lookup(each.value, "platform", local.workers_group_defaults["platform"]) == "windows" ? local.workers_group_defaults["root_block_device_name_windows"] : local.workers_group_defaults["root_block_device_name"],
    )

    ebs {
      volume_size = lookup(
        each.value,
        "root_volume_size",
        local.workers_group_defaults["root_volume_size"],
      )
      volume_type = lookup(
        each.value,
        "root_volume_type",
        local.workers_group_defaults["root_volume_type"],
      )
      iops = lookup(
        each.value,
        "root_iops",
        local.workers_group_defaults["root_iops"],
      )
      throughput = lookup(
        each.value,
        "root_volume_throughput",
        local.workers_group_defaults["root_volume_throughput"],
      )
      encrypted = lookup(
        each.value,
        "root_encrypted",
        local.workers_group_defaults["root_encrypted"],
      )
      kms_key_id = lookup(
        each.value,
        "root_kms_key_id",
        local.workers_group_defaults["root_kms_key_id"],
      )
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = lookup(each.value, "additional_ebs_volumes", local.workers_group_defaults["additional_ebs_volumes"])
    content {
      device_name = block_device_mappings.value.block_device_name

      ebs {
        volume_size = lookup(
          block_device_mappings.value,
          "volume_size",
          local.workers_group_defaults["root_volume_size"],
        )
        volume_type = lookup(
          block_device_mappings.value,
          "volume_type",
          local.workers_group_defaults["root_volume_type"],
        )
        iops = lookup(
          block_device_mappings.value,
          "iops",
          local.workers_group_defaults["root_iops"],
        )
        throughput = lookup(
          block_device_mappings.value,
          "throughput",
          local.workers_group_defaults["root_volume_throughput"],
        )
        encrypted = lookup(
          block_device_mappings.value,
          "encrypted",
          local.workers_group_defaults["root_encrypted"],
        )
        kms_key_id = lookup(
          block_device_mappings.value,
          "kms_key_id",
          local.workers_group_defaults["root_kms_key_id"],
        )
        snapshot_id = lookup(
          block_device_mappings.value,
          "snapshot_id",
          local.workers_group_defaults["snapshot_id"],
        )
        delete_on_termination = lookup(block_device_mappings.value, "delete_on_termination", true)
      }
    }

  }

  dynamic "block_device_mappings" {
    for_each = lookup(each.value, "additional_instance_store_volumes", local.workers_group_defaults["additional_instance_store_volumes"])
    content {
      device_name = block_device_mappings.value.block_device_name
      virtual_name = lookup(
        block_device_mappings.value,
        "virtual_name",
        local.workers_group_defaults["instance_store_virtual_name"],
      )
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
      {
        "Name" = "${local.cluster_name}-${lookup(
          each.value,
          "name",
          "",
        )}-eks_asg"
      },
      var.tags,
      {
        for tag in lookup(each.value, "tags", local.workers_group_defaults["tags"]) :
        tag["key"] => tag["value"]
        if tag["key"] != "Name" && tag["propagate_at_launch"]
      }
    )
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
        "Name" = "${local.cluster_name}-${lookup(
          each.value,
          "name",
          "",
        )}-eks_asg"
      },
      { for tag_key, tag_value in var.tags :
        tag_key => tag_value
        if tag_key != "Name" && !contains([for tag in lookup(each.value, "tags", local.workers_group_defaults["tags"]) : tag["key"]], tag_key)
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"

    tags = merge(
      {
        "Name" = "${local.cluster_name}-${lookup(
          each.value,
          "name",
          "",
        )}-eks_asg"
      },
      var.tags,
      {
        for tag in lookup(each.value, "tags", local.workers_group_defaults["tags"]) :
        tag["key"] => tag["value"]
        if tag["key"] != "Name" && tag["propagate_at_launch"]
      }
    )
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }

  # Prevent premature access of security group roles and policies by pods that
  # require permissions on create/destroy that depend on workers.
  depends_on = [
    aws_security_group_rule.workers_egress_internet,
    aws_security_group_rule.workers_ingress_self,
    aws_security_group_rule.workers_ingress_cluster,
    aws_security_group_rule.workers_ingress_cluster_kubelet,
    aws_security_group_rule.workers_ingress_cluster_https,
    aws_security_group_rule.workers_ingress_cluster_primary,
    aws_security_group_rule.cluster_primary_ingress_workers,
    aws_iam_role_policy_attachment.workers_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.workers_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.workers_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.workers_additional_policies
  ]
}

resource "aws_iam_instance_profile" "workers_map" {
  //count = var.manage_worker_iam_resources && var.create_eks ? local.worker_group_launch_template_count : 0
  for_each = var.manage_worker_iam_resources ? tomap(var.workers_map) : {}

  name_prefix = local.cluster_name
  role = lookup(
    each.value,
    "iam_role_id",
    local.default_iam_role_id,
  )
  path = var.iam_path

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
