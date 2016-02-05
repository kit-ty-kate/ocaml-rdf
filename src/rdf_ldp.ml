
let ldp_str = "http://www.w3.org/ns/ldp#";;
let ldp = Iri.of_string ldp_str ;;
let ldp_ s = Iri.of_string (ldp_str ^ s);;

let c_BasicContainer = ldp_ "BasicContainer" ;;
let constrainedBy = ldp_ "constrainedBy" ;;
let c_Container = ldp_ "Container" ;;
let contains = ldp_ "contains" ;;
let c_DirectContainer = ldp_ "DirectContainer" ;;
let hasMemberRelation = ldp_ "hasMemberRelation" ;;
let c_IndirectContainer = ldp_ "IndirectContainer" ;;
let insertedContentRelation = ldp_ "insertedContentRelation" ;;
let isMemberOfRelation = ldp_ "isMemberOfRelation" ;;
let member = ldp_ "member" ;;
let membershipResource = ldp_ "membershipResource" ;;
let c_NonRDFSource = ldp_ "NonRDFSource" ;;
let c_Page = ldp_ "Page" ;;
let pageSequence = ldp_ "pageSequence" ;;
let pageSortCollation = ldp_ "pageSortCollation" ;;
let pageSortCriteria = ldp_ "pageSortCriteria" ;;
let c_PageSortCriterion = ldp_ "PageSortCriterion" ;;
let pageSortOrder = ldp_ "pageSortOrder" ;;
let pageSortPredicate = ldp_ "pageSortPredicate" ;;
let c_RDFSource = ldp_ "RDFSource" ;;
let c_Resource = ldp_ "Resource" ;;

module Open = struct
  let ldp_c_BasicContainer = c_BasicContainer
  let ldp_constrainedBy = constrainedBy
  let ldp_c_Container = c_Container
  let ldp_contains = contains
  let ldp_c_DirectContainer = c_DirectContainer
  let ldp_hasMemberRelation = hasMemberRelation
  let ldp_c_IndirectContainer = c_IndirectContainer
  let ldp_insertedContentRelation = insertedContentRelation
  let ldp_isMemberOfRelation = isMemberOfRelation
  let ldp_member = member
  let ldp_membershipResource = membershipResource
  let ldp_c_NonRDFSource = c_NonRDFSource
  let ldp_c_Page = c_Page
  let ldp_pageSequence = pageSequence
  let ldp_pageSortCollation = pageSortCollation
  let ldp_pageSortCriteria = pageSortCriteria
  let ldp_c_PageSortCriterion = c_PageSortCriterion
  let ldp_pageSortOrder = pageSortOrder
  let ldp_pageSortPredicate = pageSortPredicate
  let ldp_c_RDFSource = c_RDFSource
  let ldp_c_Resource = c_Resource
end
