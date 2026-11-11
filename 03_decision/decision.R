annualized_capital <- function(capital,rate,years) {
  if(anyNA(c(capital,rate,years)) || years<=0 || rate<0) stop('Invalid capital recovery inputs')
  if(rate==0) capital/years else capital*rate/(1-(1+rate)^(-years))
}

run_decision <- function(config,inputs=load_inputs(config),comfort=NULL) {
  validate_inputs(config,inputs)
  if(is.null(comfort)) comfort<-run_comfort(config,inputs)
  a<-comfort$comparison
  a$annual_cost<-NA_real_; a$feasible<-FALSE; a$safety_pass<-FALSE
  for(i in seq_len(nrow(a))) {
    cost<-inputs$costs[inputs$costs$venue_id==a$venue_id[i] & inputs$costs$option_id==a$option_id[i],,drop=FALSE]
    lim<-inputs$constraints[inputs$constraints$venue_id==a$venue_id[i],,drop=FALSE]
    sc<-inputs$scenarios[inputs$scenarios$case_id==a$case_id[i],,drop=FALSE]
    sf<-inputs$safety[inputs$safety$case_id==a$case_id[i],,drop=FALSE]
    if(nrow(cost)!=1 || nrow(lim)!=1 || nrow(sf)!=1) stop('Cost, constraint, safety keys must resolve once')
    if(is.na(a$comfort_fraction[i])) stop('Undefined comfort fraction cannot establish adequacy')
    a$annual_cost[i]<-annualized_capital(cost$capital+cost$installation,cost$discount_rate,cost$life_years)+
      cost$maintenance_year+cost$other_annual+cost$demand_annual+
      sc$annual_weight*(a$energy_kWh[i]*cost$electricity_per_kWh+a$water_kg[i]*cost$water_per_kg)
    a$safety_pass[i]<-sf$passes==1L && sf$method==lim$safety_method
    a$safety_status[i]<-if(a$safety_pass[i]) 'screen_passed' else 'screen_failed_or_inapplicable'
    a$feasible[i]<-a$annual_cost[i]<=lim$budget_annual && a$energy_kWh[i]<=lim$energy_kWh &&
      a$water_kg[i]<=lim$water_kg && a$comfort_fraction[i]>=lim$min_comfort_fraction &&
      (lim$safety_required==0L || a$safety_pass[i])
  }
  regrets<-decisions<-guidelines<-list()
  for(venue in unique(a$venue_id)) for(variant in unique(a$model_variant[a$venue_id==venue])) {
    v<-a[a$venue_id==venue & a$model_variant==variant,,drop=FALSE]
    scenarios<-unique(v$scenario_id); options<-unique(v$option_id)
    if(anyDuplicated(paste(v$scenario_id,v$option_id)) || nrow(v)!=length(scenarios)*length(options)) stop('Incomplete or duplicate scenario-option matrix')
    robust<-options[vapply(options,function(o) all(v$feasible[v$option_id==o]),logical(1))]
    v$regret<-NA_real_
    for(s in scenarios) {
      ix<-which(v$scenario_id==s)
      candidates<-ix[v$feasible[ix] & (config$comparator=='scenario' | v$option_id[ix] %in% robust)]
      if(length(candidates)) v$regret[ix]<-v$residual_person_degC_h[ix]-min(v$residual_person_degC_h[candidates])
    }
    regrets[[length(regrets)+1L]]<-v
    if(!length(robust)) {
      decisions[[length(decisions)+1L]]<-data.frame(venue_id=venue,model_variant=variant,option_id=NA_character_,
        max_regret=NA_real_,worst_absolute_loss=NA_real_,recommended=FALSE,status='no_feasible_option')
      next
    }
    summary<-do.call(rbind,lapply(robust,function(o) {
      b<-v[v$option_id==o,]
      data.frame(venue_id=venue,model_variant=variant,option_id=o,max_regret=max(b$regret),
        worst_absolute_loss=max(b$residual_person_degC_h),recommended=FALSE,status='robust_feasible')
    }))
    summary$recommended<-summary$max_regret<=min(summary$max_regret)+config$tie_tolerance
    decisions[[length(decisions)+1L]]<-summary
    for(o in summary$option_id[summary$recommended]) for(s in scenarios) {
      b<-v[v$option_id==o & v$scenario_id==s,]
      guidelines[[length(guidelines)+1L]]<-data.frame(venue_id=venue,scenario_id=s,condition=paste('Observed inputs match scenario',s),
        action=o,reason='Minimum maximum regret within declared tolerance',result_case_id=b$case_id,
        expected_residual_person_degC_h=b$residual_person_degC_h,expected_energy_kWh=b$energy_kWh,
        limits='Only evaluated horizon, population, equipment and conditions',contingency='Outside evaluated envelope: performance unevaluated; do not extrapolate')
    }
  }
  comparisons<-do.call(rbind,lapply(split(a,paste(a$venue_id,a$scenario_id,a$model_variant)),function(v) {
    v$highest_efficiency<-FALSE; ix<-which(is.finite(v$efficiency_person_degC_h_kWh))
    if(length(ix)) v$highest_efficiency[ix]<-v$efficiency_person_degC_h_kWh[ix]>=max(v$efficiency_person_degC_h_kWh[ix])-config$tie_tolerance
    v$lowest_cost_feasible<-FALSE; ix<-which(v$feasible)
    if(length(ix)) v$lowest_cost_feasible[ix]<-v$annual_cost[ix]<=min(v$annual_cost[ix])+config$tie_tolerance
    v
  }))
  list(resources=a,regret=do.call(rbind,regrets),decision=do.call(rbind,decisions),
    guidelines=if(length(guidelines)) do.call(rbind,guidelines) else data.frame(status='no_feasible_option; contingency not evaluated'),
    comparisons=comparisons)
}

evaluate_core <- function(config,inputs) {
  validate_inputs(config,inputs)
  p<-run_physics(config,inputs); c<-run_comfort(config,inputs,p)
  list(physics=p,comfort=c,decision=run_decision(config,inputs,c))
}

write_project_results <- function(config,inputs,result) {
  save_table<-function(x,folder,name) write.csv(x,file.path(config$root,folder,name),row.names=FALSE,na='')
  p<-result$physics; c<-result$comfort; d<-result$decision
  save_table(p$zone_conditions,'01_physics','result_zone_conditions.csv')
  save_table(p$resources,'01_physics','result_device_resources.csv')
  save_table(c$detail,'02_comfort','result_comfort_detail.csv')
  save_table(c$disparities,'02_comfort','result_zone_group_disparities.csv')
  for(role in c('bus','rail','real')) {
    a<-c$comparison[c$comparison$case_id %in% inputs$scenarios$case_id[inputs$scenarios$venue_role==role],,drop=FALSE]
    name<-switch(role,bus='result_bus_comparison.csv',rail='result_rail_revision.csv',real='result_venue_comparison.csv')
    save_table(a,'02_comfort',name)
  }
  save_table(scaling_check(c),'02_comfort','result_scaling_checks.csv')
  for(pair in list(c('resources','result_costs_resources.csv'),c('resources','result_feasibility.csv'),
    c('regret','result_regret_matrix.csv'),c('decision','result_decision_comparison.csv'),c('guidelines','result_operating_guidelines.csv'),c('comparisons','result_benchmark_comparison.csv')))
    save_table(d[[pair[1]]],'03_decision',pair[2])
  writeLines(c('PROVISIONAL computed results; verification is recorded separately.',
    'No result establishes medical safety. SET benefit is not thermodynamic COP.',
    'Rail variant impacts and recovery require matched approved partitions; inspect case IDs.',
    paste('Run ID:',config$run_id)),file.path(config$root,'03_decision','result_summary.txt'))
  req<-data.frame(requirement=c('1','2a','2b','3','4','5'),status='provisional',
    output_file=c('freezer_to_shelter.txt','../02_comfort/result_bus_comparison.csv','../02_comfort/result_rail_revision.csv','../02_comfort/result_venue_comparison.csv','result_decision_comparison.csv','result_operating_guidelines.csv'),
    key_result='Use keyed result rows; independent verification not yet established',assumptions='See config and registry',
    unresolved_gaps='See check reports and README limitations')
  save_table(req,'03_decision','result_requirement_answers.csv')
  for(brief in c('result_coo_brief.txt','result_blog_brief.txt')) {
    lines<-apply(d$resources,1,function(a) paste0('Case ',a['case_id'],': residual discomfort ',a['residual_person_degC_h'],
      ' person-degC-h; electricity ',a['energy_kWh'],' kWh; water ',a['water_kg'],' kg. Source: result_costs_resources.csv, case_id=',a['case_id']))
    writeLines(c('Provisional numerical evidence; select a venue and audience before publication.',lines),file.path(config$root,'03_decision',brief))
  }
  invisible(result)
}

run_project <- function(config,run_sensitivity=TRUE,run_monte_carlo=FALSE) {
  inputs<-load_inputs(config)
  validate_inputs(config,inputs,run_sensitivity,run_monte_carlo)
  result<-evaluate_core(config,inputs)
  # Compute all requested modules before writing successful analysis outputs.
  sensitivity_result<-if(run_sensitivity) get('run_sensitivity',mode='function')(config,inputs,result) else NULL
  mc_result<-if(run_monte_carlo) get('run_monte_carlo',mode='function')(config,inputs) else NULL
  write_project_results(config,inputs,result)
  if(!is.null(sensitivity_result)) write_sensitivity_results(config,sensitivity_result)
  if(!is.null(mc_result)) write.csv(mc_result,file.path(config$root,'04_sensitivity','result_monte_carlo_summary.csv'),row.names=FALSE)
  writeLines(c(capture.output(sessionInfo()),paste('comf:',as.character(utils::packageVersion('comf')))),
    file.path(config$root,'03_decision','result_session.txt'))
  invisible(list(core=result,sensitivity=sensitivity_result,monte_carlo=mc_result))
}

run_checks_decision <- function(config) {
  data.frame(check=c('zero discount capital recovery','regret and robust feasibility','cost horizon weights','no feasible option','baseline validation guards'),
    status=c('PASS','BLOCKED','BLOCKED','BLOCKED','BLOCKED'),reason=c('Function branch implements capital / life exactly; structural inspection',
      'Real complete scenario matrix required','Explicit annual weights required','Real constraints required','Run documented structural checks'))
}
