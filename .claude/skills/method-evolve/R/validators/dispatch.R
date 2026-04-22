# validators/dispatch.R — picks a validator by slot_cfg$kind.
#
# Each validator file in validators/ is auto-sourced by cli.R (recursive).

validate_proposal <- function(payload, slot_cfg) {
  switch(slot_cfg$kind,
    feature_set     = validate_feature_set(payload, slot_cfg),
    hyperparameters = validate_hyperparameters(payload, slot_cfg),
    formula         = validate_formula(payload, slot_cfg),
    me_stop("unknown slot.kind: %s", slot_cfg$kind)
  )
}
