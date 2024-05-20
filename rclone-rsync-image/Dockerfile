FROM python:alpine

COPY requirements.txt ./
RUN apk update
RUN apk upgrade
RUN apk add --update py-pip python3-dev alpine-sdk libffi libffi-dev openssl openssl-dev gcc libc-dev make curl cargo rsync autoconf automake fts fts-dev bash openssh jq
RUN python -m pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt
RUN git clone "https://github.com/martymac/fpart.git"
WORKDIR /fpart
RUN autoreconf -i
RUN ./configure
RUN make
RUN make install
RUN curl https://rclone.org/install.sh | sed -E 's/unzip_tools_list=.+/unzip_tools_list=\("busybox"\)/g' | bash

RUN  mkdir /root/.ssh
RUN chmod 700 /root/.ssh
RUN ssh-keygen -q -t rsa -N '' -f /root/.ssh/id_rsa
WORKDIR /usr/src/app
COPY . .
RUN chmod 755 run.sh

CMD ["/usr/src/app/run.sh" ]
