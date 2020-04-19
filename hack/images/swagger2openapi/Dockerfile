# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

################################################################################
##                         INSTALL SWAGGER2OPENAPI                            ##
################################################################################
FROM node:latest as build
RUN mkdir swagger2openapi && cd swagger2openapi && npm install swagger2openapi

################################################################################
##                           RUN SWAGGER2OPENAPI                              ##
################################################################################
FROM gcr.io/distroless/nodejs:latest
LABEL "maintainer" "Andrew Kutz <akutz@vmware.com>"
COPY --from=build /swagger2openapi/ /swagger2openapi/
WORKDIR /build
CMD [ "/swagger2openapi/node_modules/swagger2openapi/swagger2openapi.js", "in.json" ]
ENTRYPOINT [ "/nodejs/bin/node" ]
