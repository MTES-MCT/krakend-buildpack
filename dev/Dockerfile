FROM scalingo/scalingo-24
ADD . buildpack

ADD .env /env/.env
RUN buildpack/bin/detect /build
RUN buildpack/bin/env.sh /env/.env /env
RUN buildpack/bin/compile /build /cache /env
RUN rm -rf /app/krakend
RUN cp -rf /build/krakend /app/krakend
EXPOSE 8080

ENTRYPOINT [ "/app/krakend/krakend", "--config",  "/app/krakend/krakend.json" ]
