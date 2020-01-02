# Dynamic Factor Model 
## This is the first time I am using Github. This message shall be shown if I am successfully push the updated version of this Read Me file. 

The project is implemented in Julia. Dynamic Factor Model involves two main steps: 
- Initialize the starting matrices (both observation, and transition matrices for Kalman Filtering). We use the principal component, and simple OLS methods to get to initial values of parameters.
- Update the parameters via maximum likelihood (in this complex multiple parameters' problems, we explore the frequentist approach by using EM algorithm). In the future, we plan to also explore estimation in Bayesian paradigm (either using Gibb's, or Metropolis-Hasting's algorithm).

The goal of this project, along with learning the models themselves, is that we try to test whether or not running this model in julia is significantly faster than the existing code in matlab.

