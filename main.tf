module "network" {
  source       = "./modules/network"
  project_name = var.project_name
}

module "security" {
  source       = "./modules/security"
  vpc_id       = module.network.vpc_id
  project_name = var.project_name
}

module "compute" {
  source              = "./modules/compute"
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  alb_sg_id           = module.security.alb_sg_id
  ec2_sg_id           = module.security.ec2_sg_id
  key_name            = var.key_name
  project_name        = var.project_name
}

module "db" {
  source             = "./modules/db"
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  ec2_sg_id          = module.security.ec2_sg_id
  db_username        = var.db_username
  db_password        = var.db_password
  project_name       = var.project_name
}

module "monitoring" {
  source                    = "./modules/monitoring"
  ec2_instance_ids          = module.compute.instance_ids
  db_instance_id            = module.db.db_instance_id
  alb_arn                   = module.compute.alb_arn
  alb_arn_suffix            = var.alb_arn_suffix
  target_group_arn_suffix   = var.target_group_arn_suffix
}
