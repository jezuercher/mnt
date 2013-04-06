function [log_Kplus,log_Kminus] = ms_compute_log_Kcat(N,KM,KV,Keq,pars);

% [log_Kplus,log_Kminus] = ms_compute_log_Kcat(N,KM,KV,Keq,pars);

ind_N               = find(N'~=0);
log_KV              = log(KV);
log_Keq             = log(Keq);
all_log_KM          = sparse(size(N,2),size(N,1));
all_log_KM(ind_N)   = log(KM(ind_N)+10^-15);
log_prod_KM         = - sum( N' .* all_log_KM , 2);
log_Kplus           = log_KV + 0.5 * ( log_Keq + log_prod_KM );
log_Kminus          = log_KV - 0.5 * ( log_Keq + log_prod_KM );