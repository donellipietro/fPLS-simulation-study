script <- sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1])
root <- normalizePath(file.path(dirname(script), "../.."))
commandArgs <- function(...) paste0('--file=',root,'/paper-figures/scripts/common.R')
source(file.path(root,'paper-figures/scripts/common.R'))
expressions <- parse(file.path(root,'paper-figures/scripts/1D_qualitative.R'))
loop_index <- which(vapply(expressions,function(x)is.call(x)&&identical(x[[1]],as.name('for')),logical(1)))[1]
checks <- quote({
 for(model in models){
  fit<-load_model(file.path(batch,paste0('batch_1_fitted_model_',model,'.RData')),model)
  raw<-fit$results$Beta_evaluation[[4]][,1]
  expected<-aligned_shape(raw,truth)
  stopifnot(isTRUE(all.equal(estimates[[model]]$evaluation,expected)))
 }
 idx<-match(data$locations[,1],data$evaluation[,1])
 stopifnot(!anyNA(idx),isTRUE(all.equal(estimates$MV_PLS$locations,estimates$MV_PLS$evaluation[idx])))
 message('k=',k,': MV-PLS agrees on both grids; all evaluation curves unchanged.')
})
body<-expressions[[loop_index]][[4]]
expressions[[loop_index]][[4]]<-as.call(c(as.list(body),list(checks)))
panel_root<-tempfile('fpls-qualitative-check-')
for(expr in expressions[-1])eval(expr)
unlink(panel_root,recursive=TRUE)
