# Sensitivity delegates all calculations to evaluate_core; no recursive run_project.
outcome_vector <- function(result) {
  d<-result$decision$decision
  data.frame(venue_id=d$venue_id,model_variant=d$model_variant,option_id=d$option_id,
    max_regret=d$max_regret,worst_absolute_loss=d$worst_absolute_loss,recommended=d$recommended,status=d$status)
}

run_sensitivity <- function(config,inputs=load_inputs(config),base=NULL) {
  validate_inputs(config,inputs,TRUE,FALSE)
  needed<-c('comfort_threshold','airflow','local_airspeed','coverage','weather','occupancy','resource_limits')
  if(any(!needed %in% inputs$uncertainty$category)) stop('Missing mandatory sensitivity categories')
  if(any(!c('rating_interpretation','zone_partition') %in% inputs$alternatives$category)) stop('Missing approved interpretation/partition alternatives')
  if(!is.function(config$sensitivity_recompute) || !is.function(config$approved_alternatives)) stop('Explicit coherent recomputation and alternative adapters required')
  if(is.null(base)) base<-evaluate_core(config,inputs)
  base_out<-outcome_vector(base); rows<-list(); u<-inputs$uncertainty
  if(any(u$levels<2L | u$lower>u$upper)) stop('Invalid sensitivity grid')
  change<-function(z,cfg,spec,value) {
    if(spec$table=='config') cfg[[spec$field]]<-value else {
      if(!spec$table %in% names(z) || !spec$field %in% names(z[[spec$table]]) || spec$row_id<1 || spec$row_id>nrow(z[[spec$table]])) stop('Invalid sensitivity target')
      z[[spec$table]][[spec$field]][spec$row_id]<-value
    }
    # Adapter must update dependent fields AND provenance, never fill missing observations.
    config$sensitivity_recompute(cfg,z,spec,value)
  }
  evaluate<-function(cfg,z,id,v1,v2=NA_real_) {
    out<-outcome_vector(evaluate_core(cfg,z)); out$sweep_id<-id; out$value_1<-v1; out$value_2<-v2
    key<-function(d) paste(d$venue_id,d$model_variant,d$option_id)
    ix<-match(key(out),key(base_out))
    out$baseline_regret<-base_out$max_regret[ix]
    out$normalized_regret_change<-ifelse(is.na(out$baseline_regret) | out$baseline_regret==0,NA_real_,(out$max_regret-out$baseline_regret)/abs(out$baseline_regret))
    out$recommendation_changed<-out$recommended!=base_out$recommended[ix]
    out
  }
  for(i in seq_len(nrow(u))) {
    spec<-u[i,]; values<-seq(spec$lower,spec$upper,length.out=spec$levels)
    for(v in values) {
      changed<-change(inputs,config,spec,v)
      rows[[length(rows)+1L]]<-evaluate(changed$config,changed$inputs,spec$sweep_id,v)
    }
    if(spec$pair_id!='NONE') {
      pair<-u[u$sweep_id==spec$pair_id,,drop=FALSE]; if(nrow(pair)!=1) stop('Invalid paired sweep')
      for(v in values) for(w in seq(pair$lower,pair$upper,length.out=pair$levels)) {
        changed<-change(inputs,config,spec,v); changed<-change(changed$inputs,changed$config,pair,w)
        rows[[length(rows)+1L]]<-evaluate(changed$config,changed$inputs,paste(spec$sweep_id,pair$sweep_id,sep='+'),v,w)
      }
    }
  }
  alternatives<-config$approved_alternatives(config,inputs)
  if(!is.list(alternatives) || !length(alternatives)) stop('No approved alternatives returned')
  for(a in alternatives) rows[[length(rows)+1L]]<-evaluate(a$config,a$inputs,a$id,NA_real_)
  result<-do.call(rbind,rows)
  cross<-list()
  for(key in unique(paste(result$sweep_id,result$venue_id,result$model_variant,result$option_id))) {
    a<-result[paste(result$sweep_id,result$venue_id,result$model_variant,result$option_id)==key,,drop=FALSE]
    if(anyNA(a$value_1) || any(!is.na(a$value_2))) next
    a<-a[order(a$value_1),]; if(nrow(a)<2) next
    for(i in seq_len(nrow(a)-1L)) if(a$recommended[i]!=a$recommended[i+1L]) cross[[length(cross)+1L]]<-data.frame(
      sweep_id=a$sweep_id[i],venue_id=a$venue_id[i],option_id=a$option_id[i],lower=a$value_1[i],upper=a$value_1[i+1L],interpretation='Tested-grid bracket; no interpolated crossover claimed')
  }
  list(detail=result,crossovers=if(length(cross)) do.call(rbind,cross) else data.frame(status='No recommendation crossover found on tested one-way grids'),
    stability=c('Conclusions apply only to supplied ranges and approved alternatives.',
      paste('Changed recommendation entries:',sum(result$recommendation_changed %in% TRUE)),
      'Undefined normalized changes remain NA when baseline regret is zero or keys differ.'))
}

write_sensitivity_results <- function(config,result) {
  p<-file.path(config$root,'04_sensitivity')
  write.csv(result$detail,file.path(p,'result_sensitivity.csv'),row.names=FALSE,na='')
  write.csv(result$crossovers,file.path(p,'result_crossovers.csv'),row.names=FALSE,na='')
  writeLines(result$stability,file.path(p,'result_stability.txt'))
}

run_monte_carlo <- function(config,inputs=load_inputs(config)) {
  validate_inputs(config,inputs,FALSE,TRUE)
  if(!is.function(config$mc_draw) || !is.function(config$mc_converged)) stop('Approved joint uncertainty sampler and convergence test required')
  if(config$mc_count<1 || config$mc_count!=as.integer(config$mc_count) || any(config$mc_probs<0 | config$mc_probs>1)) stop('Invalid Monte Carlo count/quantiles')
  set.seed(config$mc_seed)
  result<-lapply(seq_len(config$mc_count),function(i) {
    draw<-config$mc_draw(config,inputs,i)
    z<-outcome_vector(evaluate_core(draw$config,draw$inputs)); z$draw_id<-i; z
  })
  all<-do.call(rbind,result)
  if(!isTRUE(config$mc_converged(all,config))) stop('Monte Carlo convergence criterion not met')
  do.call(rbind,lapply(split(all,paste(all$venue_id,all$model_variant,all$option_id)),function(a) {
    q<-quantile(a$max_regret,probs=config$mc_probs,names=FALSE,type=1)
    data.frame(venue_id=a$venue_id[1],option_id=a$option_id[1],quantile=config$mc_probs,
      regret=q,sampled_selection_fraction=mean(a$recommended),samples=nrow(a),
      interpretation='Conditional on documented joint uncertainty model; not confidence intervals or unconditional probabilities')
  }))
}

run_checks_sensitivity <- function(config) {
  data.frame(check=c('one-way and two-way grids','interpretation and partition alternatives','coherent dependent updates','Monte Carlo convergence'),
    status='BLOCKED',reason=c('Evidence-backed bounds and selected pairs missing','Approved alternatives missing','Approved adapter and sources missing','Disabled; authorization and joint uncertainty model missing'))
}
